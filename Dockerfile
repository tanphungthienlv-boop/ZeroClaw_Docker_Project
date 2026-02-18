# Use official Rust image as build stage
FROM rust:latest AS builder
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
    && rm -rf /var/lib/apt/lists/*

# Copy compiled ZeroClaw binary
COPY --from=builder /app/target/release/zeroclaw /usr/local/bin/zeroclaw

# Set up workspace
WORKDIR /root/.zeroclaw
EXPOSE 8080

# Start Gateway
CMD ["zeroclaw", "gateway"]
