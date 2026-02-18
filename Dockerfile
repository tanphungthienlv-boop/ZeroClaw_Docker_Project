# Use official Rust image as build stage
FROM rust:1-bookworm AS builder
WORKDIR /app
COPY . .
RUN cargo build --release

# Use lightweight Debian for runtime
FROM debian:bookworm-slim

# Install Node.js & Chromium (for browser automation tools)
RUN apt-get update && apt-get install -y \
    nodejs \
    npm \
    chromium \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled ZeroClaw binary
COPY --from=builder /app/target/release/zeroclaw /usr/local/bin/zeroclaw

# Set up workspace
WORKDIR /root/.zeroclaw
EXPOSE 8080

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Copy config template for entrypoint generation
COPY config/config.toml.example /app/config/config.toml.example

# Start Daemon with Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

