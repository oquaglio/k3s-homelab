FROM docker.io/library/postgres:17

# Install MinIO Client (mc) for S3-compatible storage operations
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget ca-certificates && \
    wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc && \
    chmod +x /usr/local/bin/mc && \
    apt-get purge -y wget && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*
