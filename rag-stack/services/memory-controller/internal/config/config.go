package config

import (
	"app-builds/common/envutil"
	"app-builds/common/tlsutil"
)

type Config struct {
	ListenAddr   string
	DBConnString string
	TLSCert      string
	TLSKey       string
}

func Load() *Config {
	insecure := tlsutil.IsInsecureAllowed()
	dbDefault := "postgres://app:app@timescaledb-rw.timescaledb.svc.cluster.local:5432/app?sslmode=require"
	if insecure {
		dbDefault = "postgres://app:app@timescaledb-rw.timescaledb.svc.cluster.local:5432/app?sslmode=disable"
	}

	return &Config{
		ListenAddr:   envutil.GetEnv("LISTEN_ADDR", ":8080"),
		DBConnString: envutil.GetEnv("DB_CONN_STRING", dbDefault),
		TLSCert:      envutil.GetEnv("TLS_CERT", ""),
		TLSKey:       envutil.GetEnv("TLS_KEY", ""),
	}
}
