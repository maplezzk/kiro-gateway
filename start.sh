#!/bin/bash
# Kiro Gateway - 启动脚本
# 用法: ./start.sh [--env <文件路径>] [--project <名称>]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 解析参数
ENV_FILE=""
PROJECT_NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env|-e)
            ENV_FILE="$2"
            shift 2
            ;;
        --project|-p|--name|-n)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --help|-h)
            echo "用法: $0 [--env <文件路径>] [--project <名称>]"
            echo ""
            echo "选项:"
            echo "  --env, -e <path>       指定配置文件路径（默认: .env）"
            echo "  --project, -p <name>   指定 docker-compose 项目名（用于多实例）"
            echo "  --name, -n <name>      同 --project"
            echo "  --help, -h             显示帮助"
            echo ""
            echo "示例:"
            echo "  $0"
            echo "  $0 --env envs/zzk/zzk.env --project zzk"
            echo "  $0 --env envs/kidd/kidd.env --project kidd"
            echo ""
            echo "多实例: 每个实例需要不同的 SERVER_PORT 和不同的 --project 名称"
            echo "默认项目名 = 配置文件 basename（去掉 .env 后缀）"
            exit 0
            ;;
        -*)
            echo "❌ 未知参数: $1"
            echo "运行 $0 --help 查看帮助"
            exit 1
            ;;
        *)
            if [ -z "$ENV_FILE" ]; then
                ENV_FILE="$1"
            else
                echo "❌ 多次指定参数: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

ENV_FILE="${ENV_FILE:-.env}"

# 转换为绝对路径
if [[ "$ENV_FILE" != /* ]]; then
    ENV_FILE="$SCRIPT_DIR/$ENV_FILE"
fi

# 检查文件存在
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ 未找到配置文件: $ENV_FILE"
    exit 1
fi

# 自动生成项目名（用 env 文件的 basename 去后缀）
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME=$(basename "$ENV_FILE" .env)
fi

# 读取 SERVER_PORT 用于健康检查
SERVER_PORT=$(grep "^SERVER_PORT=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"')
SERVER_PORT="${SERVER_PORT:-8000}"

echo "🚀 Kiro Gateway 启动中..."
echo "📄 配置文件: $ENV_FILE"
echo "🏷️  项目名: $PROJECT_NAME"
echo "🔌 端口: $SERVER_PORT"

# 生成 docker-compose override 文件，指定自定义 env_file
# 这样不会动 .env，每个实例独立
OVERRIDE_FILE="$SCRIPT_DIR/.docker-compose.override.${PROJECT_NAME}.yml"
cat > "$OVERRIDE_FILE" <<EOF
services:
  kiro-gateway:
    env_file:
      - $ENV_FILE
EOF

# 确保退出时清理 override 文件
trap 'rm -f "$OVERRIDE_FILE"' EXIT

# 检查凭证文件（如果配置了 KIRO_CREDS_FILE）
CREDS_FILE=$(grep "^KIRO_CREDS_FILE=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"')
if [ -n "$CREDS_FILE" ]; then
    LOCAL_CREDS="${CREDS_FILE/\/home\/kiro/$HOME}"
    if [ ! -f "$LOCAL_CREDS" ]; then
        echo "❌ 未找到凭证文件: $LOCAL_CREDS"
        echo "   请确认 Kiro IDE 已登录并生成凭证文件"
        exit 1
    fi
    echo "✅ 凭证文件已找到: $LOCAL_CREDS"
fi

# 启动容器（指定项目名 + override 文件）
echo "🏗️  构建并启动容器...（每次强制重建镜像以使用最新代码）"
docker-compose -p "$PROJECT_NAME" -f docker-compose.yml -f "$OVERRIDE_FILE" up -d --build

# 等待健康检查通过
echo "⏳ 等待服务就绪（端口 $SERVER_PORT）..."
for i in $(seq 1 15); do
    if curl -sf "http://localhost:$SERVER_PORT/health" > /dev/null 2>&1; then
        echo "✅ Kiro Gateway 启动成功！"
        echo ""
        echo "   📍 地址: http://localhost:$SERVER_PORT"
        echo "   🏷️  项目: $PROJECT_NAME"
        echo "   🔑 API Key: $(grep "^PROXY_API_KEY=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"')"
        echo "   📋 模型列表: curl -H \"Authorization: Bearer \$(grep ^PROXY_API_KEY= $ENV_FILE | cut -d'=' -f2 | tr -d '\"')\" http://localhost:$SERVER_PORT/v1/models"
        echo "   📜 查看日志: docker-compose -p $PROJECT_NAME logs -f"
        exit 0
    fi
    sleep 1
done

echo "❌ 服务启动超时，请查看日志: docker-compose -p $PROJECT_NAME logs -f"
exit 1
