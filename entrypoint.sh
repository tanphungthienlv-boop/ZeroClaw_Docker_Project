#!/bin/bash
set -e

# Define paths
CONFIG_DIR="/root/.zeroclaw"
CONFIG_FILE="$CONFIG_DIR/config.toml"
TEMPLATE_FILE="/app/config/config.toml.example"
GEMINI_DIR="/root/.gemini"
OAUTH_CREDS_FILE="$GEMINI_DIR/oauth_creds.json"

# Ensure directories exist
mkdir -p "$CONFIG_DIR"
mkdir -p "$GEMINI_DIR"

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

    # Parse using Python3 for reliable JSON handling
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

    # Calculate expiry (1 hour from now) in RFC3339 format
    EXPIRY=$(python3 -c "
from datetime import datetime, timezone, timedelta
expiry = datetime.now(timezone.utc) + timedelta(hours=1)
print(expiry.strftime('%Y-%m-%dT%H:%M:%SZ'))
")

    # Write token to ~/.gemini/oauth_creds.json (where ZeroClaw's Gemini provider reads it)
    python3 -c "
import json
creds = {
    'access_token': '$ACCESS_TOKEN',
    'expiry': '$EXPIRY'
}
with open('$OAUTH_CREDS_FILE', 'w') as f:
    json.dump(creds, f, indent=2)
"
    chmod 600 "$OAUTH_CREDS_FILE"
    echo "✅ Access Token written to $OAUTH_CREDS_FILE"
}

# ── Background Token Refresh Loop ────────────────────────────────────
token_refresh_loop() {
    while true; do
        sleep 3000  # Refresh every 50 minutes
        echo "🔄 Refreshing Google Access Token..."
        fetch_access_token
        if [ $? -eq 0 ]; then
            echo "✅ Token refreshed at $(date)"
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
