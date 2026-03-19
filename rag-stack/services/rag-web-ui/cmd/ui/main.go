package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"app-builds/common/telemetry"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/google/uuid"
	_ "github.com/lib/pq"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

var (
	bucketName string
	s3Client   *s3.Client
	db         *sql.DB
	llmURL     string
	llmModel   string
	version    = "v4.0.0-interactive"
)

func initEnv() {
	dbConn := os.Getenv("DB_CONN_STRING")
	if dbConn != "" {
		var err error
		db, err = sql.Open("postgres", dbConn)
		if err != nil {
			log.Printf("Warning: Could not connect to DB: %v", err)
		}
	}

	endpoint := os.Getenv("S3_ENDPOINT")
	if endpoint != "" && !strings.HasPrefix(endpoint, "http") {
		endpoint = "https://" + endpoint
	}
	bucketName = os.Getenv("BUCKET_NAME")
	llmURL = os.Getenv("LLM_URL")
	if llmURL == "" {
		llmURL = "https://llm-gateway.rag-system.svc.cluster.local/v1/chat/completions"
	}
	llmModel = os.Getenv("LLM_MODEL")
	if llmModel == "" {
		llmModel = "llama3.1"
	}

	customResolver := aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
		return aws.Endpoint{
			URL:               endpoint,
			HostnameImmutable: true,
		}, nil
	})

	cfg, err := config.LoadDefaultConfig(context.TODO(),
		config.WithEndpointResolverWithOptions(customResolver),
		config.WithRegion("us-east-1"),
	)
	if err != nil {
		log.Printf("unable to load SDK config, %v", err)
	} else {
		s3Client = s3.NewFromConfig(cfg, func(o *s3.Options) {
			o.UsePathStyle = true
		})
	}
}

type Tag struct {
	ID      string
	Name    string
	HasData bool
}

type Session struct {
	ID          string
	Name        string
	Description string
	CreatedAt   time.Time
}

type Message struct {
	ID             string
	Role           string
	Content        string
	CreatedAt      time.Time
	SequenceNumber int
}

func ingestionPageHandler(w http.ResponseWriter, r *http.Request) {
	data := struct {
		Files   []string
		Tags    []Tag
		Version string
		Page    string
	}{
		Version: version,
		Page:    "ingestion",
	}

	if s3Client != nil {
		resp, err := s3Client.ListObjectsV2(context.TODO(), &s3.ListObjectsV2Input{
			Bucket: aws.String(bucketName),
		})
		if err != nil {
			log.Printf("Error listing S3 objects: %v", err)
		} else {
			for _, item := range resp.Contents {
				data.Files = append(data.Files, *item.Key)
			}
		}
	}

	if db != nil {
		rows, err := db.Query("SELECT t.tag_id, t.tag_name, EXISTS (SELECT 1 FROM code_ingestion_tag cit WHERE cit.tag_id = t.tag_id) as has_data FROM tag t ORDER BY t.tag_name")
		if err != nil {
			log.Printf("Error querying tags: %v", err)
		} else {
			defer rows.Close()
			for rows.Next() {
				var t Tag
				if err := rows.Scan(&t.ID, &t.Name, &t.HasData); err != nil {
					log.Printf("Error scanning tag: %v", err)
					continue
				}
				data.Tags = append(data.Tags, t)
			}
		}
	}

	renderTemplate(w, data)
}

func chatPageHandler(w http.ResponseWriter, r *http.Request) {
	data := struct {
		Files   []string
		Tags    []Tag
		Version string
		Page    string
	}{
		Version: version,
		Page:    "chat",
	}

	if db != nil {
		rows, err := db.Query("SELECT tag_id, tag_name FROM tag ORDER BY tag_name")
		if err != nil {
			log.Printf("Error querying tags for chat: %v", err)
		} else {
			defer rows.Close()
			for rows.Next() {
				var t Tag
				if err := rows.Scan(&t.ID, &t.Name); err != nil {
					log.Printf("Error scanning tag for chat: %v", err)
					continue
				}
				data.Tags = append(data.Tags, t)
			}
		}
	}

	renderTemplate(w, data)
}

func getSessionsHandler(w http.ResponseWriter, r *http.Request) {
	var sessions []Session
	if db != nil {
		rows, err := db.Query("SELECT session_id, name, description, created_at FROM sessions ORDER BY created_at DESC")
		if err != nil {
			log.Printf("Error querying sessions: %v", err)
		} else {
			defer rows.Close()
			for rows.Next() {
				var s Session
				var desc sql.NullString
				if err := rows.Scan(&s.ID, &s.Name, &desc, &s.CreatedAt); err != nil {
					log.Printf("Error scanning session: %v", err)
					continue
				}
				s.Description = desc.String
				sessions = append(sessions, s)
			}
		}
	}
	json.NewEncoder(w).Encode(sessions)
}

func getHistoryHandler(w http.ResponseWriter, r *http.Request) {
	sessionID := r.URL.Query().Get("session_id")
	keyword := r.URL.Query().Get("keyword")

	var history []Message
	if db != nil && sessionID != "" {
		query := `
			(SELECT prompt_id::text as id, 'user' as role, content, created_at, 0 as seq 
			 FROM prompts WHERE session_id = $1)
			UNION ALL
			(SELECT response_id::text as id, 'assistant' as role, content, created_at, sequence_number as seq 
			 FROM responses WHERE session_id = $1)
			ORDER BY created_at ASC, seq ASC`
		rows, err := db.Query(query, sessionID)
		if err != nil {
			log.Printf("Error querying history for session %s: %v", sessionID, err)
		} else {
			defer rows.Close()
			for rows.Next() {
				var m Message
				if err := rows.Scan(&m.ID, &m.Role, &m.Content, &m.CreatedAt, &m.SequenceNumber); err != nil {
					log.Printf("Error scanning history message: %v", err)
					continue
				}
				if keyword != "" && !strings.Contains(strings.ToLower(m.Content), strings.ToLower(keyword)) {
					continue
				}
				history = append(history, m)
			}
		}
	}
	json.NewEncoder(w).Encode(history)
}

func askHandler(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Query       string   `json:"query"`
		SessionID   string   `json:"session_id"`
		SessionName string   `json:"session_name"`
		SessionDesc string   `json:"session_desc"`
		Tags        []string `json:"tags"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	sID := req.SessionID
	if sID == "" {
		sID = uuid.New().String()
		if db != nil {
			_, err := db.Exec("INSERT INTO sessions (session_id, name, description) VALUES ($1, $2, $3) ON CONFLICT (session_id) DO NOTHING", sID, req.SessionName, req.SessionDesc)
			if err != nil {
				log.Printf("Error creating session %s: %v", sID, err)
			}
		}
	}

	if db != nil && len(req.Tags) > 0 {
		if _, err := db.Exec("DELETE FROM session_tag WHERE session_id = $1", sID); err != nil {
			log.Printf("Error deleting session tags for %s: %v", sID, err)
		}
		for _, tID := range req.Tags {
			if _, err := db.Exec("INSERT INTO session_tag (session_id, tag_id) VALUES ($1, $2) ON CONFLICT DO NOTHING", sID, tID); err != nil {
				log.Printf("Error inserting session tag %s for session %s: %v", tID, sID, err)
			}
		}
	}

	payload := map[string]interface{}{"model": llmModel, "session_id": sID, "messages": []map[string]string{{"role": "user", "content": req.Query}}}
	body, _ := json.Marshal(payload)
	resp, err := http.Post(llmURL, "application/json", bytes.NewBuffer(body))
	if err != nil {
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	defer resp.Body.Close()

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
		Error string `json:"error"`
	}
	json.NewDecoder(resp.Body).Decode(&result)

	answer := ""
	if len(result.Choices) > 0 {
		answer = result.Choices[0].Message.Content
	}
	json.NewEncoder(w).Encode(map[string]interface{}{"answer": answer, "session_id": sID})
}

func uploadHandler(w http.ResponseWriter, r *http.Request) {
	r.ParseMultipartForm(500 << 20)
	files := r.MultipartForm.File["file"]
	for _, fh := range files {
		f, err := fh.Open()
		if err != nil {
			log.Printf("Error opening uploaded file %s: %v", fh.Filename, err)
			continue
		}
		_, err = s3Client.PutObject(context.TODO(), &s3.PutObjectInput{Bucket: aws.String(bucketName), Key: aws.String(fh.Filename), Body: f})
		if err != nil {
			log.Printf("Error uploading file %s to S3: %v", fh.Filename, err)
		}
		f.Close()
	}
	w.WriteHeader(http.StatusNoContent)
}

func triggerIngestHandler(w http.ResponseWriter, r *http.Request) {
	r.ParseForm()
	tags := r.Form["tags"]
	if db != nil {
		var ingestionID string
		err := db.QueryRow("INSERT INTO code_ingestion (s3_bucket_id) VALUES ($1) RETURNING ingestion_id", bucketName).Scan(&ingestionID)
		if err != nil {
			log.Printf("Error starting ingestion: %v", err)
			http.Error(w, "Failed to start ingestion", http.StatusInternalServerError)
			return
		}
		for _, tid := range tags {
			if _, err := db.Exec("INSERT INTO code_ingestion_tag (ingestion_id, tag_id) VALUES ($1, $2)", ingestionID, tid); err != nil {
				log.Printf("Error linking tag %s to ingestion %s: %v", tid, ingestionID, err)
			}
		}
		go func() {
			var tNames []string
			for _, tid := range tags {
				var n string
				if err := db.QueryRow("SELECT tag_name FROM tag WHERE tag_id = $1", tid).Scan(&n); err != nil {
					log.Printf("Error fetching tag name for %s: %v", tid, err)
					continue
				}
				tNames = append(tNames, n)
			}
			p, _ := json.Marshal(map[string]interface{}{"ingestion_id": ingestionID, "tag_names": tNames, "tag_ids": tags})
			resp, err := http.Post("https://rag-ingestion-service.rag-system.svc.cluster.local/ingest", "application/json", bytes.NewBuffer(p))
			if err != nil {
				log.Printf("Error triggering ingestion service: %v", err)
			} else {
				resp.Body.Close()
			}
		}()
	}
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func createTagHandler(w http.ResponseWriter, r *http.Request) {
	name := r.FormValue("tag_name")
	if name != "" && db != nil {
		if _, err := db.Exec("INSERT INTO tag (tag_name) VALUES ($1) ON CONFLICT DO NOTHING", name); err != nil {
			log.Printf("Error creating tag %s: %v", name, err)
		}
	}
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func deleteDataHandler(w http.ResponseWriter, r *http.Request) {
	r.ParseForm()
	tags := r.Form["tags"]
	for _, tid := range tags {
		if _, err := db.Exec("DELETE FROM code_ingestion WHERE ingestion_id IN (SELECT ingestion_id FROM code_ingestion_tag WHERE tag_id = $1)", tid); err != nil {
			log.Printf("Error deleting ingestion for tag %s: %v", tid, err)
		}
	}
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func healthHandler(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }

func renderTemplate(w http.ResponseWriter, data interface{}) {
	tmpl := `
	<!DOCTYPE html>
	<html>
	<head>
		<title>RAG Control Center</title>
		<style>
			body { font-family: 'Segoe UI', sans-serif; margin: 0; background: #121212; color: #e0e0e0; display: flex; height: 100vh; overflow: hidden; }
			.sidebar { width: 240px; background: #1e1e1e; border-right: 1px solid #333; padding: 20px; display: flex; flex-direction: column; }
			.main-content { flex: 1; display: flex; flex-direction: column; overflow-y: auto; padding: 20px; }
			.nav-item { padding: 12px; margin-bottom: 8px; border-radius: 6px; cursor: pointer; color: #bbb; text-decoration: none; }
			.nav-item:hover, .nav-item.active { background: #333; color: white; }
			.section { background: #1e1e1e; border: 1px solid #333; border-radius: 8px; padding: 20px; margin-bottom: 20px; }
			.btn { padding: 10px 16px; border-radius: 4px; border: none; cursor: pointer; background: #2196F3; color: white; }
			.btn-success { background: #4CAF50; }
			.btn-danger { background: #f44336; }
			input[type="text"], select, textarea { background: #2d2d2d; border: 1px solid #444; color: white; padding: 10px; border-radius: 4px; }
			#chat-history { flex: 1; overflow-y: auto; padding: 20px; background: #181818; border-radius: 8px; border: 1px solid #333; margin-bottom: 20px; display: flex; flex-direction: column; }
			.msg { margin-bottom: 15px; padding: 12px; border-radius: 8px; max-width: 80%; }
			.msg-user { align-self: flex-end; background: #0d47a1; }
			.msg-assistant { align-self: flex-start; background: #333; }
			.query-box { background: #1e1e1e; padding: 20px; border: 1px solid #333; border-radius: 8px; }
			.multi-select { height: 100px; overflow-y: auto; border: 1px solid #444; padding: 5px; background: #2d2d2d; }
			.modal { display: none; position: fixed; z-index: 100; left: 0; top: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); }
			.modal-content { background: #1e1e1e; margin: 10% auto; padding: 20px; border: 1px solid #333; width: 60%; border-radius: 8px; }
		</style>
	</head>
	<body>
		<div class="sidebar">
			<h2 style="color:white; margin-top:0;">RAG Stack</h2>
			<a href="/" class="nav-item {{if eq .Page "ingestion"}}active{{end}}">📥 Data Ingestion</a>
			<a href="/chat" class="nav-item {{if eq .Page "chat"}}active{{end}}">💬 Interactive Chat</a>
			<div style="flex:1"></div>
			<div style="font-size: 0.8em; color: #666;">{{.Version}}</div>
		</div>
		<div class="main-content">
			{{if eq .Page "ingestion"}}
				<h1>Data Ingestion</h1>
				<div class="section">
					<h3>Upload Source Code</h3>
					<input type="file" id="fileInput" multiple style="display:none" onchange="handleSelection()">
					<button onclick="document.getElementById('fileInput').click()" class="btn btn-success">Choose Files...</button>
					<div id="fileList" style="margin-top:10px;"></div>
					<button onclick="uploadFiles()" class="btn" style="margin-top:10px; width:100%">Upload to S3</button>
				</div>
				<div class="section">
					<h3>Ingest & Tag</h3>
					<form action="/trigger-ingest" method="post">
						<div class="multi-select">
							{{range .Tags}}
								<label style="display:block;"><input type="checkbox" name="tags" value="{{.ID}}"> {{.Name}}</label>
							{{end}}
						</div>
						<button type="submit" class="btn btn-success" style="margin-top:10px;">Start Ingestion</button>
					</form>
					<hr style="border:0; border-top:1px solid #333; margin:20px 0;">
					<form action="/create-tag" method="post">
						<input type="text" name="tag_name" placeholder="New tag name...">
						<button type="submit" class="btn">Create Tag</button>
					</form>
				</div>
			{{else if eq .Page "chat"}}
				<div style="display:flex; justify-content:space-between; align-items:center;">
					<h1>Ask the RAG</h1>
					<button class="btn" onclick="showSessions()">📂 History</button>
				</div>
				<div class="query-box">
					<div style="display:flex; gap:10px; margin-bottom:10px;">
						<input type="text" id="sessionName" placeholder="Session Name" style="flex:1">
						<input type="text" id="sessionDesc" placeholder="Description" style="flex:2">
					</div>
					<div class="multi-select" style="margin-bottom:10px;">
						{{range .Tags}}
							<label style="display:inline-block; margin-right:15px;"><input type="checkbox" class="chat-tag" value="{{.ID}}"> {{.Name}}</label>
						{{end}}
					</div>
					<div style="display:flex; gap:10px;">
						<textarea id="query" style="flex:1; height:60px; background:#2d2d2d; color:white;" placeholder="Prompt..."></textarea>
						<button class="btn" id="askBtn" onclick="ask()" style="height:60px; width:80px;">Send</button>
					</div>
				</div>
				<div style="margin:20px 0; display:flex; gap:10px;">
					<input type="text" id="keyword" placeholder="Search history..." oninput="loadHistory()" style="flex:1">
				</div>
				<div id="chat-history"></div>
			{{end}}
		</div>
		<div id="sessionModal" class="modal"><div class="modal-content"><h3>Recent Sessions</h3><div id="sessionList"></div><button class="btn" onclick="document.getElementById('sessionModal').style.display='none'">Close</button></div></div>
		<script>
		let currentSessionID = "";
		async function ask() {
			const query = document.getElementById('query').value; if (!query) return;
			const tags = Array.from(document.querySelectorAll('.chat-tag:checked')).map(cb => cb.value);
			const payload = { query: query, session_id: currentSessionID, session_name: document.getElementById('sessionName').value, session_desc: document.getElementById('sessionDesc').value, tags: tags };
			const res = await fetch('/ask', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(payload) });
			const data = await res.json(); if (data.session_id) currentSessionID = data.session_id;
			document.getElementById('query').value = ""; loadHistory();
		}
		async function loadHistory() {
			if (!currentSessionID) return;
			const res = await fetch("/history?session_id=" + currentSessionID + "&keyword=" + document.getElementById('keyword').value);
			const msgs = await res.json();
			document.getElementById('chat-history').innerHTML = msgs.map(m => '<div class="msg msg-'+m.Role+'"><strong>'+m.Role+'</strong>: '+m.Content+'</div>').join('');
		}
		async function showSessions() {
			const res = await fetch("/sessions"); const sessions = await res.json();
			document.getElementById('sessionList').innerHTML = sessions.map(s => '<div style="padding:10px; border-bottom:1px solid #333; cursor:pointer;" onclick="selectSession(\''+s.ID+'\', \''+s.Name+'\', \''+s.Description+'\')">'+s.Name+' - '+s.Description+'</div>').join('');
			document.getElementById('sessionModal').style.display = 'block';
		}
		function selectSession(id, name, desc) {
			currentSessionID = id; document.getElementById('sessionName').value = name; document.getElementById('sessionDesc').value = desc;
			document.getElementById('sessionModal').style.display = 'none'; loadHistory();
		}
		function handleSelection() { document.getElementById('fileList').innerHTML = Array.from(document.getElementById('fileInput').files).map(f => '<div>'+f.name+'</div>').join(''); }
		async function uploadFiles() {
			const formData = new FormData(); Array.from(document.getElementById('fileInput').files).forEach(f => formData.append("file", f));
			await fetch("/upload", {method: 'POST', body: formData}); alert("Uploaded!"); location.reload();
		}
		</script>
	</body>
	</html>`
	t := template.Must(template.New("layout").Parse(tmpl))
	t.Execute(w, data)
}

func main() {
	initEnv()

	shutdown, err := telemetry.InitTracer("rag-web-ui")
	if err != nil {
		log.Printf("Warning: failed to initialize tracer: %v", err)
	} else {
		defer shutdown(context.Background())
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", ingestionPageHandler)
	mux.HandleFunc("/chat", chatPageHandler)
	mux.HandleFunc("/sessions", getSessionsHandler)
	mux.HandleFunc("/history", getHistoryHandler)
	mux.HandleFunc("/ask", askHandler)
	mux.HandleFunc("/upload", uploadHandler)
	mux.HandleFunc("/trigger-ingest", triggerIngestHandler)
	mux.HandleFunc("/create-tag", createTagHandler)
	mux.HandleFunc("/delete-data", deleteDataHandler)
	mux.HandleFunc("/health", healthHandler)

	otelHandler := otelhttp.NewHandler(mux, "rag-web-ui")

	server := &http.Server{
		Addr:    ":8080",
		Handler: otelHandler,
	}

	go func() {
		certFile := os.Getenv("TLS_CERT")
		keyFile := os.Getenv("TLS_KEY")
		if certFile != "" && keyFile != "" {
			fmt.Printf("RAG Interactive UI v4 listening with TLS on :8080\n")
			if err := server.ListenAndServeTLS(certFile, keyFile); err != nil && err != http.ErrServerClosed {
				log.Fatalf("Listen error: %v", err)
			}
		} else {
			fmt.Printf("RAG Interactive UI v4 listening on :8080\n")
			if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Fatalf("Listen error: %v", err)
			}
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Println("Shutting down RAG Web UI...")
}
