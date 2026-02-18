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
        --data-urlencode "client_id=${GOOGLE_CLIENT_ID}" \
        --data-urlencode "client_secret=${GOOGLE_CLIENT_SECRET}" \
        --data-urlencode "refresh_token=${GOOGLE_REFRESH_TOKEN}" \
        --data-urlencode "grant_type=refresh_token")

    ACCESS_TOKEN=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    token = data.get('access_token', '')
    if token:
        print(token)
    else:
        print('ERROR: ' + str(data), file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print('PARSE_ERROR: ' + str(e), file=sys.stderr)
    sys.exit(1)
")

    if [ $? -ne 0 ] || [ -z "$ACCESS_TOKEN" ]; then
        echo "❌ Failed to parse Access Token from response"
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
        sleep 3000  # Refresh every 50 minutes
        echo "🔄 Refreshing Google Access Token..."
        RESPONSE=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
            --data-urlencode "client_id=${GOOGLE_CLIENT_ID}" \
            --data-urlencode "client_secret=${GOOGLE_CLIENT_SECRET}" \
            --data-urlencode "refresh_token=${GOOGLE_REFRESH_TOKEN}" \
            --data-urlencode "grant_type=refresh_token")

        NEW_TOKEN=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    token = data.get('access_token', '')
    if token:
        print(token)
    else:
        sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null)

        if [ -n "$NEW_TOKEN" ]; then
            echo "$NEW_TOKEN" > "$TOKEN_FILE"
            chmod 600 "$TOKEN_FILE"
            export ZEROCLAW_API_KEY="$NEW_TOKEN"
            echo "✅ Access Token refreshed at $(date)"
        else
            echo "⚠️  Token refresh failed at $(date)"
        fi
    done
}

# ── Generate Config File (first run only) ────────────────────────────
if [ ! -f "$CONFIG_FILE" ]; then
    echo "📜 Generating config.toml from template..."
    cp "$TEMPLATE_FILE" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    # Replace Telegram Token
    TG_TOKEN=${TELEGRAM_TOKEN:-$TELEGRAM_BOT_TOKEN}
    if [ -n "$TG_TOKEN" ]; then
        echo "✅ Injecting Telegram token..."
        sed -i "s|YOUR_TELEGRAM_BOT_TOKEN_HERE|$TG_TOKEN|g" "$CONFIG_FILE"
    else
        echo "⚠️  No Telegram token found (checked TELEGRAM_TOKEN and TELEGRAM_BOT_TOKEN)"
    fi
fi

# ── Get Initial Access Token ─────────────────────────────────────────
fetch_access_token

# ── Start Background Token Refresh ───────────────────────────────────
token_refresh_loop &
echo "🔄 Token auto-refresh started (every 50 min)"

# ── Start ZeroClaw Daemon ─────────────────────────────────────────────
echo "🚀 Starting ZeroClaw Daemon..."
exec zeroclaw daemon --host 0.0.0.0
