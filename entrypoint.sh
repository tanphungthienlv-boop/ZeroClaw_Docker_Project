#!/bin/bash
set -e

# Define paths
CONFIG_DIR="/root/.zeroclaw"
CONFIG_FILE="$CONFIG_DIR/config.toml"
TEMPLATE_FILE="/app/config/config.toml.example"

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "📜 Generating config.toml from template..."
    cp "$TEMPLATE_FILE" "$CONFIG_FILE"

    # Replace Telegram Token
    if [ -n "$TELEGRAM_TOKEN" ]; then
        echo "✅ Injecting TELEGRAM_TOKEN..."
        sed -i "s|YOUR_TELEGRAM_BOT_TOKEN_HERE|$TELEGRAM_TOKEN|g" "$CONFIG_FILE"
    else
        echo "⚠️  TELEGRAM_TOKEN not set! Bot may not work."
        # Debugging: Print env vars to see what's available (masked)
        env | grep -v 'KEY\|TOKEN\|SECRET\|PASSWORD' || true
    fi

    # Replace Groq API Key
    if [ -n "$GROQ_API_KEY" ]; then
        echo "✅ Injecting GROQ_API_KEY..."
        sed -i "s|YOUR_GROQ_API_KEY_HERE|$GROQ_API_KEY|g" "$CONFIG_FILE"
    fi

    # Replace Gemini/Custom API Key if provided as ZEROCLAW_API_KEY
    # (Note: The app handles ZEROCLAW_API_KEY automatically via env override, 
    # but we can also inject it into the commented out line if we want explicit config)
    # The example file has: # api_key = "..."
    # We'll leave it to the app's internal env override logic for ZEROCLAW_API_KEY.

    # Ensure binding to 0.0.0.0 for external access
    # specific fix if template has 127.0.0.1 (though our example has it right/wrong depending on version)
    # Our example config doesn't specify host, so it defaults to 127.0.0.1 in code.
    # We NEED to add it explicitly or use CLI arg.
    # But wait, config.toml.example DOES have [gateway] section but no host key in the example I read?
    # Let me check the file content trace again.
    # config.toml.example has:
    # [gateway]
    # require_pairing = false
    # allow_public_bind = true
    # It DOES NOT have "host = ..."
    
    # So we should append it or rely on CLI arg --host 0.0.0.0
fi

echo "🚀 Starting ZeroClaw Daemon..."
# Explicitly bind to 0.0.0.0 and use the config we just generated
exec zeroclaw daemon --host 0.0.0.0
