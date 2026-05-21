#!/bin/bash
# Kiro Gateway - 停止脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🛑 Kiro Gateway 停止中..."
docker-compose down
echo "✅ 已停止"
