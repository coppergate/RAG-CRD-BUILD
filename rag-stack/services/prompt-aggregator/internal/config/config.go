package config

import (
	"time"

	"app-builds/common/envutil"
	"app-builds/common/tlsutil"
)

type Config struct {
	PulsarURL             string
	PulsarResultsTopic    string
	PulsarCompletionTopic string
	PulsarSubscription    string
	AggregationTimeout    time.Duration
}

func LoadConfig() *Config {
	insecure := tlsutil.IsInsecureAllowed()
	pulsarDefault := "pulsar+ssl://pulsar-proxy.apache-pulsar.svc.cluster.local:6651"
	if insecure {
		pulsarDefault = "pulsar://pulsar-proxy.apache-pulsar.svc.cluster.local:6650"
	}

	return &Config{
		PulsarURL:             envutil.GetEnv("PULSAR_URL", pulsarDefault),
		PulsarResultsTopic:    envutil.GetEnv("PULSAR_RESULTS_TOPIC", "persistent://rag-pipeline/stage/results"),
		PulsarCompletionTopic: envutil.GetEnv("PULSAR_COMPLETION_TOPIC", "persistent://rag-pipeline/stage/completion"),
		PulsarSubscription:    envutil.GetEnv("PULSAR_SUBSCRIPTION", "prompt-aggregator-sub"),
		AggregationTimeout:    envutil.GetEnvDuration("AGGREGATION_TIMEOUT", 60*time.Second),
	}
}
