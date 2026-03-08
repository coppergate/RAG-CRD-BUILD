FROM registry.hierocracy.home:5000/python:3.9-slim

WORKDIR /app

# Install system dependencies for psycopg2
RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Build context is /workspace with service folders under it.
COPY rag-ingestion/requirements.txt ./requirements.txt
RUN python -m pip install --upgrade pip==26.0.1 \
    && pip --version \
    && pip install --no-cache-dir -r requirements.txt

# Copy source
COPY rag-ingestion/service.py ./service.py

CMD ["uvicorn", "service:app", "--host", "0.0.0.0", "--port", "8000"]
