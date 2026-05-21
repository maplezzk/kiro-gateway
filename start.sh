#!/bin/bash
# Kiro Gateway - 启动脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Kiro Gateway 启动中..."

# 检查 .env 文件
if [ ! -f .env ]; then
    echo "❌ 未找到 .env 文件！请先执行: cp .env.example .env 并配置"
    exit 1
fi

# 检查凭证文件（如果配置了 KIRO_CREDS_FILE）
CREDS_FILE=$(grep "^KIRO_CREDS_FILE=" .env | cut -d'=' -f2 | tr -d '"')
if [ -n "$CREDS_FILE" ]; then
    # 将容器内路径转换为本地路径
    LOCAL_CREDS="${CREDS_FILE/\/home\/kiro/$HOME}"
    if [ ! -f "$LOCAL_CREDS" ]; then
        echo "❌ 未找到凭证文件: $LOCAL_CREDS"
        echo "   请确认 Kiro IDE 已登录并生成凭证文件"
        exit 1
    fi
    echo "✅ 凭证文件已找到: $LOCAL_CREDS"
fi

# 启动容器
echo "🏗️  构建并启动容器...（每次强制重建镜像以使用最新代码）"
docker-compose up -d --build

# 等待健康检查通过
echo "⏳ 等待服务就绪..."
for i in $(seq 1 15); do
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        echo "✅ Kiro Gateway 启动成功！"
        echo ""
        echo "   📍 地址: http://localhost:8000"
        echo "   🔑 API Key: $(grep "^PROXY_API_KEY=" .env | cut -d'=' -f2 | tr -d '"')"
        echo "   📋 模型列表: curl -H \"Authorization: Bearer \$(grep ^PROXY_API_KEY= .env | cut -d'=' -f2 | tr -d '\"')\" http://localhost:8000/v1/models"
        echo "   📜 查看日志: docker-compose logs -f"
        exit 0
    fi
    sleep 1
done

echo "❌ 服务启动超时，请查看日志: docker-compose logs -f"
exit 1
