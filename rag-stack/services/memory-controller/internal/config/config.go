package config

import (
	"app-builds/common/envutil"
	"app-builds/common/tlsutil"
)

type Config struct {
	ListenAddr   string
	DBConnString string
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
	}
}
