# Stage 1: Build Flutter Web
FROM registry.hierocracy.home:5000/debian:bookworm-slim AS build

# Install dependencies for Flutter
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Flutter stable channel
RUN git clone https://github.com/flutter/flutter.git /usr/local/flutter -b stable
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Prepare the application directory
WORKDIR /app
COPY . .

# Ensure web files exist
RUN flutter create . --platforms=web

# Fetch dependencies and build for web
RUN flutter pub get
RUN flutter build web --release

# Stage 2: Serve the static files using Busybox HTTPD
FROM registry.hierocracy.home:5000/alpine:3.23.3

# Use busybox httpd to serve static files. 
# It is included by default in Alpine's busybox.
WORKDIR /www
COPY --from=build /app/build/web .

# Serve on port 8080 (aligned with other services)
EXPOSE 8080

CMD ["httpd", "-f", "-v", "-p", "8080", "-h", "/www"]
