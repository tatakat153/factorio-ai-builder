#!/bin/bash
# Factorio AI Builder - Bridge Service Launcher
# Usage: ./start-bridge.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/bridge"

echo "Starting Factorio AI Builder Bridge on http://localhost:9380"
echo "RCON target: ${RCON_HOST:-127.0.0.1}:${RCON_PORT:-34198}"
echo ""

python3 main.py
