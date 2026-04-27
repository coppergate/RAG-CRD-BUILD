package tlsutil

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

// LoadCACertPool reads the CA certificate file specified by SSL_CERT_FILE
// and returns a certificate pool. Returns an error if the file cannot be read
// or contains no valid certificates.
func LoadCACertPool() (*x509.CertPool, error) {
	caFile := os.Getenv("SSL_CERT_FILE")
	if caFile == "" {
		return nil, fmt.Errorf("SSL_CERT_FILE environment variable is not set")
	}

	caCert, err := os.ReadFile(caFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read CA certificate file %s: %w", caFile, err)
	}

	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(caCert) {
		return nil, fmt.Errorf("CA certificate file %s contains no valid certificates", caFile)
	}

	return pool, nil
}

// NewTLSConfig builds a *tls.Config using the CA pool from SSL_CERT_FILE.
// Returns an error if the CA cannot be loaded.
func NewTLSConfig() (*tls.Config, error) {
	pool, err := LoadCACertPool()
	if err != nil {
		return nil, err
	}
	return &tls.Config{
		RootCAs: pool,
	}, nil
}

// NewHTTPClient returns an HTTP client configured for TLS when useTLS is true.
// When TLS is enabled, it loads the Hierocracy CA from SSL_CERT_FILE for
// proper certificate verification. Returns an error if TLS is requested
// but the CA cannot be loaded.
func NewHTTPClient(useTLS bool, timeout time.Duration) (*http.Client, error) {
	transport := &http.Transport{}

	if useTLS {
		tlsCfg, err := NewTLSConfig()
		if err != nil {
			return nil, fmt.Errorf("cannot create TLS HTTP client: %w", err)
		}
		transport.TLSClientConfig = tlsCfg
	}

	return &http.Client{
		Timeout:   timeout,
		Transport: transport,
	}, nil
}

// PulsarTLSCertPath returns the SSL_CERT_FILE path for use as the Pulsar
// client's TLSTrustCertsFilePath. Returns an empty string if TLS is not
// being used (URL does not start with "pulsar+ssl://").
func PulsarTLSCertPath(pulsarURL string) string {
	if !strings.HasPrefix(pulsarURL, "pulsar+ssl://") {
		return ""
	}
	caFile := os.Getenv("SSL_CERT_FILE")
	if caFile == "" {
		log.Printf("WARNING: Pulsar URL uses TLS (%s) but SSL_CERT_FILE is not set", pulsarURL)
	}
	return caFile
}

// IsInsecureAllowed checks whether the ALLOW_INSECURE environment variable
// is explicitly set to "true". This must be set to use non-TLS defaults.
func IsInsecureAllowed() bool {
	return os.Getenv("ALLOW_INSECURE") == "true"
}

// RequireTLS logs a fatal error and exits if TLS is expected but not
// configured. Use this during service startup to enforce TLS.
func RequireTLS(componentName string) {
	if IsInsecureAllowed() {
		log.Printf("WARNING: %s running in INSECURE mode (ALLOW_INSECURE=true)", componentName)
		return
	}
	caFile := os.Getenv("SSL_CERT_FILE")
	if caFile == "" {
		log.Printf("WARNING: %s: SSL_CERT_FILE is not set. Set ALLOW_INSECURE=true to run without TLS.", componentName)
	}
}

// URLScheme returns "https" if useTLS is true, "http" otherwise.
func URLScheme(useTLS bool) string {
	if useTLS {
		return "https"
	}
	return "http"
}
