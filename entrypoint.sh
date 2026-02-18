#!/bin/bash
set -e

# Define paths
CONFIG_DIR="/root/.zeroclaw"
CONFIG_FILE="$CONFIG_DIR/config.toml"
TEMPLATE_FILE="/app/config/config.toml.example"
TOKEN_FILE="$CONFIG_DIR/.access_token"

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# ── OAuth Token Exchange Function ─────────────────────────────────────
fetch_access_token() {
    if [ -z "$GOOGLE_REFRESH_TOKEN" ] || [ -z "$GOOGLE_CLIENT_ID" ] || [ -z "$GOOGLE_CLIENT_SECRET" ]; then
        echo "⚠️  Missing OAuth credentials (GOOGLE_REFRESH_TOKEN, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET)"
        return 1
    fi

    echo "🔑 Fetching Google Access Token..."
    RESPONSE=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
        -d "client_id=${GOOGLE_CLIENT_ID}" \
        -d "client_secret=${GOOGLE_CLIENT_SECRET}" \
        -d "refresh_token=${GOOGLE_REFRESH_TOKEN}" \
        -d "grant_type=refresh_token")

    ACCESS_TOKEN=$(echo "$RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$ACCESS_TOKEN" ]; then
        echo "❌ Failed to get Access Token. Response: $RESPONSE"
        return 1
    fi

    echo "$ACCESS_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    export ZEROCLAW_API_KEY="$ACCESS_TOKEN"
    echo "✅ Access Token obtained successfully."
}

# ── Background Token Refresh Loop ────────────────────────────────────
token_refresh_loop() {
    while true; do
        # Wait 50 minutes (3000 seconds) before refreshing
        sleep 3000
        echo "🔄 Refreshing Google Access Token..."
        RESPONSE=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
            -d "client_id=${GOOGLE_CLIENT_ID}" \
            -d "client_secret=${GOOGLE_CLIENT_SECRET}" \
            -d "refresh_token=${GOOGLE_REFRESH_TOKEN}" \
            -d "grant_type=refresh_token")

        NEW_TOKEN=$(echo "$RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

        if [ -n "$NEW_TOKEN" ]; then
            echo "$NEW_TOKEN" > "$TOKEN_FILE"
            chmod 600 "$TOKEN_FILE"
            # Update the env var for any new processes
            export ZEROCLAW_API_KEY="$NEW_TOKEN"
            echo "✅ Access Token refreshed at $(date)"
        else
            echo "⚠️  Token refresh failed at $(date). Response: $RESPONSE"
        fi
    done
}

# ── Generate Config File (first run only) ────────────────────────────
if [ ! -f "$CONFIG_FILE" ]; then
    echo "📜 Generating config.toml from template..."
    cp "$TEMPLATE_FILE" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    # Replace Telegram Token (Support both TELEGRAM_TOKEN and TELEGRAM_BOT_TOKEN)
    TG_TOKEN=${TELEGRAM_TOKEN:-$TELEGRAM_BOT_TOKEN}
    if [ -n "$TG_TOKEN" ]; then
        echo "✅ Injecting Telegram token..."
        sed -i "s|YOUR_TELEGRAM_BOT_TOKEN_HERE|$TG_TOKEN|g" "$CONFIG_FILE"
    else
        echo "⚠️  No Telegram token found (checked TELEGRAM_TOKEN and TELEGRAM_BOT_TOKEN)"
    fi

    # Replace Groq API Key
    if [ -n "$GROQ_API_KEY" ]; then
        echo "✅ Injecting GROQ_API_KEY..."
        sed -i "s|YOUR_GROQ_API_KEY_HERE|$GROQ_API_KEY|g" "$CONFIG_FILE"
    fi
fi

# ── Get Initial Access Token ─────────────────────────────────────────
fetch_access_token

# ── Start Background Token Refresh ───────────────────────────────────
token_refresh_loop &
REFRESH_PID=$!
echo "🔄 Token refresh loop started (PID: $REFRESH_PID)"

# ── Start ZeroClaw Daemon ─────────────────────────────────────────────
echo "🚀 Starting ZeroClaw Daemon..."
exec zeroclaw daemon --host 0.0.0.0
