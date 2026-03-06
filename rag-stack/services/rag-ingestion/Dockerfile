FROM python:3.9-slim

WORKDIR /app

# Install system dependencies for psycopg2
RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install
COPY requirements.txt .
RUN python -m pip install --upgrade pip==26.0.1 \
    && pip --version \
    && pip install --no-cache-dir -r requirements.txt

# Copy source
COPY service.py .

CMD ["uvicorn", "service:app", "--host", "0.0.0.0", "--port", "8000"]
