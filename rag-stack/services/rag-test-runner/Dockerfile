FROM registry.hierocracy.home:5000/python:3.9-slim

# Install system dependencies for pulsar-client and psycopg2
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    make \
    libpq-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Pre-install python packages (add verbosity, tracing, schema validation)
RUN python -m pip install --upgrade pip==26.0.1 \
    && pip --version \
    && pip install --no-cache-dir \
    boto3 \
    requests \
    qdrant-client \
    pulsar-client \
    psycopg2-binary \
    jsonschema \
    opentelemetry-api \
    opentelemetry-sdk \
    opentelemetry-exporter-otlp \
    sentence-transformers \
    torch --extra-index-url https://download.pytorch.org/whl/cpu

WORKDIR /tests

# Default command to keep container alive or be overridden by Job
CMD ["python", "--version"]
