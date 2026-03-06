package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/apache/pulsar-client-go/pulsar"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

type BuildTask struct {
	ServiceName    string `json:"service_name"`
	Version        string `json:"version"`
	DockerfilePath string `json:"dockerfile_path"`
	SourceTarball  string `json:"source_tarball"`
	SourceURL      string `json:"source_url"`
	Registry       string `json:"registry"`
}

func main() {
	pulsarURL := os.Getenv("PULSAR_URL")
	topic := os.Getenv("BUILD_TOPIC")
	if pulsarURL == "" || topic == "" {
		log.Fatal("PULSAR_URL and BUILD_TOPIC must be set")
	}

	// K8s client
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("Error building in-cluster config: %v", err)
	}
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatalf("Error creating kubernetes client: %v", err)
	}

	// Pulsar client
	client, err := pulsar.NewClient(pulsar.ClientOptions{
		URL: pulsarURL,
	})
	if err != nil {
		log.Fatalf("Could not instantiate Pulsar client: %v", err)
	}
	defer client.Close()

	consumer, err := client.Subscribe(pulsar.ConsumerOptions{
		Topic:            topic,
		SubscriptionName: "build-orchestrator-sub",
		Type:             pulsar.Shared,
	})
	if err != nil {
		log.Fatalf("Could not subscribe to topic: %v", err)
	}
	defer consumer.Close()

	log.Printf("Build Orchestrator listening on %s", topic)

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() {
		for {
			msg, err := consumer.Receive(ctx)
			if err != nil {
				if ctx.Err() != nil {
					return
				}
				log.Printf("Error receiving message: %v", err)
				continue
			}

			var task BuildTask
			if err := json.Unmarshal(msg.Payload(), &task); err != nil {
				log.Printf("Error unmarshaling task: %v", err)
				consumer.Ack(msg)
				continue
			}

			log.Printf("Received build task for %s:%s", task.ServiceName, task.Version)

			if err := launchKanikoJob(ctx, clientset, task); err != nil {
				log.Printf("Error launching kaniko job: %v", err)
				consumer.Nack(msg)
			} else {
				consumer.Ack(msg)
			}
		}
	}()

	<-sigChan
	log.Println("Shutting down build orchestrator")
}

func launchKanikoJob(ctx context.Context, clientset *kubernetes.Clientset, task BuildTask) error {
	jobName := fmt.Sprintf("kaniko-build-%s-%s", task.ServiceName, task.Version)
	namespace := "build-pipeline"

	// Delete existing job if it exists (for retries)
	_ = clientset.BatchV1().Jobs(namespace).Delete(ctx, jobName, metav1.DeleteOptions{
		PropagationPolicy: ptr(metav1.DeletePropagationForeground),
	})

	// Use pre-signed URL context if available, fallback to S3 scheme
	contextURL := task.SourceURL
	if contextURL == "" {
		// Fallback to S3 scheme if no URL provided (requires Kaniko to support it)
		contextURL = "s3://$(BUCKET_NAME)/" + task.SourceTarball
	}

	job := &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Name:      jobName,
			Namespace: namespace,
		},
		Spec: batchv1.JobSpec{
			Template: corev1.PodTemplateSpec{
				Spec: corev1.PodSpec{
					InitContainers: []corev1.Container{
						{
							Name:  "fetch-context",
							Image: "busybox",
							Command: []string{"sh", "-c"},
							Args: []string{
								fmt.Sprintf("wget -O /workspace/context.tar.gz \"%s\" && tar -xzof /workspace/context.tar.gz -C /workspace && rm /workspace/context.tar.gz", contextURL),
							},
							SecurityContext: &corev1.SecurityContext{
								AllowPrivilegeEscalation: ptr(false),
								Capabilities: &corev1.Capabilities{
									Drop: []corev1.Capability{"ALL"},
								},
								RunAsNonRoot: ptr(true),
								RunAsUser:    ptr(int64(1000)),
								SeccompProfile: &corev1.SeccompProfile{
									Type: corev1.SeccompProfileTypeRuntimeDefault,
								},
							},
							VolumeMounts: []corev1.VolumeMount{
								{
									Name:      "workspace",
									MountPath: "/workspace",
								},
							},
						},
					},
					Containers: []corev1.Container{
						{
							Name:  "kaniko",
							Image: "gcr.io/kaniko-project/executor:latest",
							Args: []string{
								"--dockerfile=" + task.DockerfilePath,
								"--context=dir:///workspace",
								"--destination=" + task.Registry + "/" + task.ServiceName + ":" + task.Version,
								"--destination=" + task.Registry + "/" + task.ServiceName + ":latest",
								"--insecure",
								"--skip-tls-verify",
							},
							SecurityContext: &corev1.SecurityContext{
								AllowPrivilegeEscalation: ptr(true),
							},
							VolumeMounts: []corev1.VolumeMount{
								{
									Name:      "workspace",
									MountPath: "/workspace",
								},
							},
							Resources: corev1.ResourceRequirements{
								Requests: corev1.ResourceList{
									corev1.ResourceCPU:    resource.MustParse("2"),
									corev1.ResourceMemory: resource.MustParse("4Gi"),
								},
								Limits: corev1.ResourceList{
									corev1.ResourceCPU:    resource.MustParse("4"),
									corev1.ResourceMemory: resource.MustParse("8Gi"),
								},
							},
						},
					},
					Volumes: []corev1.Volume{
						{
							Name: "workspace",
							VolumeSource: corev1.VolumeSource{
								EmptyDir: &corev1.EmptyDirVolumeSource{},
							},
						},
					},
					RestartPolicy: corev1.RestartPolicyNever,
				},
			},
			BackoffLimit: ptr(int32(1)),
		},
	}

	// Add AWS credentials and endpoint only if fallback to S3 is needed in the init container
	// (Note: Currently fetch-context uses busybox/wget which doesn't support s3://)
	if task.SourceURL == "" {
		// If we wanted to support s3:// in init container, we'd swap image to amazon/aws-cli
		// and add EnvFrom here. For now, we assume SourceURL is always provided by scripts.
		job.Spec.Template.Spec.InitContainers[0].EnvFrom = []corev1.EnvFromSource{
			{
				SecretRef: &corev1.SecretEnvSource{
					LocalObjectReference: corev1.LocalObjectReference{Name: "build-pipeline-bucket"},
				},
			},
			{
				ConfigMapRef: &corev1.ConfigMapEnvSource{
					LocalObjectReference: corev1.LocalObjectReference{Name: "build-pipeline-bucket"},
				},
			},
		}
	}

	_, err := clientset.BatchV1().Jobs(namespace).Create(ctx, job, metav1.CreateOptions{})
	return err
}

// Helpers
func ptr[T any](v T) *T { return &v }
