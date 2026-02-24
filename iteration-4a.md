### APM install (Grafana LGTM) 

 Create namespace `monitoring` if missing and label it for privileged Pod Security Standards:
  - `pod-security.kubernetes.io/audit=privileged`
  - `pod-security.kubernetes.io/warn=privileged`
  - `pod-security.kubernetes.io/enforce=privileged`
- Provision S3 Object Bucket Claims for LGTM storage by applying `common/s3-storage.yaml` in `monitoring` and wait until the following secrets/configmaps exist (poll loop until secret present):
  - `loki-s3-bucket`, `tempo-s3-bucket`, `mimir-s3-bucket`, `mimir-ruler-s3-bucket`, `mimir-alertmanager-s3-bucket`.
- For each component, generate Helm values from a template with `envsubst`, using S3 creds pulled from the OBC resources in `monitoring`:
  - Common per-component vars from the component’s bucket name (`$bucket_secret`):
    - From ConfigMap: `BUCKET_HOST -> S3_ENDPOINT`, `BUCKET_NAME -> BUCKET_NAME`.
    - From Secret: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (base64‑decoded).
  - For `mimir`, also extract dedicated buckets and credentials:
    - Ruler: `mimir-ruler-s3-bucket` -> `RULER_BUCKET_NAME`, `RULER_ACCESS_KEY`, `RULER_SECRET_KEY`.
    - Alertmanager: `mimir-alertmanager-s3-bucket` -> `ALERTMANAGER_BUCKET_NAME`, `ALERTMANAGER_ACCESS_KEY`, `ALERTMANAGER_SECRET_KEY`.
  - Render to `/tmp/<name>-values.yaml` from `$REPO_DIR/<name>/values.yaml.template` via `envsubst`.
- Helm repo setup for all installs: `helm repo add grafana https://grafana.github.io/helm-charts && helm repo update`.
- Install/upgrade LGTM components with Helm (namespace `monitoring`, `--wait --timeout 15m --debug`, using the rendered values file):
  - Loki: `helm upgrade --install loki grafana/loki`.
  - Tempo (distributed):
    - Pre‑cleanup legacy resources to avoid conflicts: delete `StatefulSet/tempo`, `Service/tempo`, and any resources labeled `app.kubernetes.io/instance=tempo` in `monitoring`.
    - Install: `helm upgrade --install tempo grafana/tempo-distributed`.
  - Mimir (distributed): `helm upgrade --install mimir grafana/mimir-distributed`.
- Deploy OpenTelemetry Collector: `kubectl apply -f $REPO_DIR/otel-collector/otel-collector.yaml` (in `monitoring`).
- Deploy Grafana via Operator:
  - Ensure Grafana Helm repo present/updated (as above).
  - `helm upgrade --install grafana-operator grafana/grafana-operator --namespace monitoring --wait`.
  - Apply `grafana/operator-manifests.yaml` to create the Grafana instance and related CRs.
- Deploy Grafana Alloy metrics scraper: `helm upgrade --install alloy grafana/alloy --namespace monitoring --values $REPO_DIR/alloy/values.yaml --wait`.
- Clear the installation journal at the end; print completion message: “Grafana LGTM Stack Installation Complete.”