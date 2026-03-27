package tlsutil

import (
	"os"
	"testing"
)

func TestLoadCACertPool_NoEnvVar(t *testing.T) {
	os.Unsetenv("SSL_CERT_FILE")
	_, err := LoadCACertPool()
	if err == nil {
		t.Fatal("expected error when SSL_CERT_FILE is not set")
	}
}

func TestLoadCACertPool_BadFile(t *testing.T) {
	t.Setenv("SSL_CERT_FILE", "/nonexistent/ca.crt")
	_, err := LoadCACertPool()
	if err == nil {
		t.Fatal("expected error for nonexistent file")
	}
}

func TestLoadCACertPool_InvalidPEM(t *testing.T) {
	tmp, _ := os.CreateTemp("", "bad-ca-*.crt")
	defer os.Remove(tmp.Name())
	tmp.WriteString("not a PEM cert")
	tmp.Close()

	t.Setenv("SSL_CERT_FILE", tmp.Name())
	_, err := LoadCACertPool()
	if err == nil {
		t.Fatal("expected error for invalid PEM")
	}
}

func TestNewTLSConfig_Success(t *testing.T) {
	// Use a valid self-signed RSA test cert
	pem := `-----BEGIN CERTIFICATE-----
MIIC/zCCAeegAwIBAgIUHpyngPDb/htk0IBqCskx46L0rTMwDQYJKoZIhvcNAQEL
BQAwDzENMAsGA1UEAwwEdGVzdDAeFw0yNjAzMjYxMzA3MjNaFw0yNjAzMjcxMzA3
MjNaMA8xDTALBgNVBAMMBHRlc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
AoIBAQDWgZ//E/HcmZ8yyE0K8nYztMcSerbCWDSwR10xYKIRP3j1qAyE6uKwV0K5
laMS2R9xEt9yw3/YVgFCHBUBZJOV128iQgXDhH09K+/oSbRDJAqhtdeAqORwzBOb
uz3VFjiVxuwkNdY18JtqFcZMdo2q3phCaQDd8sI7GFnqcr+r8ni2epp87o5DrGRs
0Ca9KcI8pFJzhcV87zOzQvJGweUUJAJWTnNF88dV7KZW6/tUYVu/vgHHvQiXIIq1
9c4R+lyPiBxXm6TCmgepszIcJcml8nU7A+2u6PyY/w6WgGAo7yAyMMXgmpxNIjYs
JTc1eDq8yg6GY8YLDmz1/wcC/R9PAgMBAAGjUzBRMB0GA1UdDgQWBBQvxI+YHjXI
p4Jmqe6KOn+kDPpxdzAfBgNVHSMEGDAWgBQvxI+YHjXIp4Jmqe6KOn+kDPpxdzAP
BgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQBoxMx53otgjvbX8NcJ
OcG9tRbZ2KhFwTdKGXnk+b4RyW8lAgJN96lB2L/iPHKbl9UEx/UEkp0vFcL0WL6C
WR1ZZSAaHeEna4NTjOuqwrY8pQFJGdbSLOiQYMxmvNNCnFMo9BgZAgfoEM8Q31GJ
qifg9gVMozYf+xgjQU1VrcD4uvBTrgNExxHqlp3wm+tWxC74cMmv77cT9H+wPIIm
YSalcixn3wnaji/ZKmVdsClo7D8EfvoW6r0opQsYzBzkr3zP6rWxidCJ9vpy25Hr
nWkX+lYpyrdtN5VPqaXuAGwnzydDz1X+WYhIi1CGBPjGQHhTcMBdeAlHaEBZ9m4y
7WrZ
-----END CERTIFICATE-----`
	tmp, _ := os.CreateTemp("", "test-ca-*.crt")
	defer os.Remove(tmp.Name())
	tmp.WriteString(pem)
	tmp.Close()

	t.Setenv("SSL_CERT_FILE", tmp.Name())
	cfg, err := NewTLSConfig()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg == nil || cfg.RootCAs == nil {
		t.Fatal("expected non-nil TLS config with RootCAs")
	}
}

func TestNewHTTPClient_NoTLS(t *testing.T) {
	client, err := NewHTTPClient(false, 0)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if client == nil {
		t.Fatal("expected non-nil client")
	}
}

func TestNewHTTPClient_TLS_NoEnv(t *testing.T) {
	os.Unsetenv("SSL_CERT_FILE")
	_, err := NewHTTPClient(true, 0)
	if err == nil {
		t.Fatal("expected error when TLS requested without SSL_CERT_FILE")
	}
}

func TestPulsarTLSCertPath_NonSSL(t *testing.T) {
	path := PulsarTLSCertPath("pulsar://localhost:6650")
	if path != "" {
		t.Fatalf("expected empty path for non-SSL URL, got %q", path)
	}
}

func TestPulsarTLSCertPath_SSL(t *testing.T) {
	t.Setenv("SSL_CERT_FILE", "/etc/ssl/certs/ca.crt")
	path := PulsarTLSCertPath("pulsar+ssl://localhost:6651")
	if path != "/etc/ssl/certs/ca.crt" {
		t.Fatalf("expected CA path, got %q", path)
	}
}

func TestIsInsecureAllowed(t *testing.T) {
	os.Unsetenv("ALLOW_INSECURE")
	if IsInsecureAllowed() {
		t.Fatal("expected false when ALLOW_INSECURE not set")
	}

	t.Setenv("ALLOW_INSECURE", "true")
	if !IsInsecureAllowed() {
		t.Fatal("expected true when ALLOW_INSECURE=true")
	}

	t.Setenv("ALLOW_INSECURE", "false")
	if IsInsecureAllowed() {
		t.Fatal("expected false when ALLOW_INSECURE=false")
	}
}

func TestURLScheme(t *testing.T) {
	if URLScheme(true) != "https" {
		t.Fatal("expected https")
	}
	if URLScheme(false) != "http" {
		t.Fatal("expected http")
	}
}
