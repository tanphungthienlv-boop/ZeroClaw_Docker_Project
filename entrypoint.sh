#!/bin/bash
set -e

# Define paths
CONFIG_DIR="/root/.zeroclaw"
CONFIG_FILE="$CONFIG_DIR/config.toml"
TEMPLATE_FILE="/app/config/config.toml.example"

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# ── ALWAYS map Railway env vars to what the app expects ──────────────
# Map TELEGRAM_BOT_TOKEN → TELEGRAM_TOKEN (for reference only, we use TG_TOKEN below)
# Map GOOGLE_REFRESH_TOKEN → ZEROCLAW_API_KEY (app reads this on every start)
if [ -z "$ZEROCLAW_API_KEY" ] && [ -n "$GOOGLE_REFRESH_TOKEN" ]; then
    echo "🔄 Mapping GOOGLE_REFRESH_TOKEN to ZEROCLAW_API_KEY..."
    export ZEROCLAW_API_KEY="$GOOGLE_REFRESH_TOKEN"
fi

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

echo "🚀 Starting ZeroClaw Daemon..."
exec zeroclaw daemon --host 0.0.0.0
