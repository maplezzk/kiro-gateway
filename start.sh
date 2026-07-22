#!/bin/bash
# Kiro Gateway - 启动脚本
# 用法: ./start.sh [--env <文件路径>] [<文件路径>]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 解析参数
ENV_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env|-e)
            ENV_FILE="$2"
            shift 2
            ;;
        --help|-h)
            echo "用法: $0 [--env <文件路径>] [<文件路径>]"
            echo ""
            echo "选项:"
            echo "  --env, -e <path>  指定配置文件路径（默认: .env）"
            echo "  --help, -h        显示帮助"
            echo ""
            echo "示例:"
            echo "  $0"
            echo "  $0 --env .env.production"
            echo "  $0 .env.staging"
            echo ""
            echo "注意: 指定自定义配置后，会将其符号链接到 .env，docker-compose 默认读取 .env。"
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
                echo "❌ 多次指定配置文件: $1"
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

echo "🚀 Kiro Gateway 启动中..."
echo "📄 配置文件: $ENV_FILE"

# 如果指定了自定义配置，链接到 .env（docker-compose 默认读取 .env）
if [ "$ENV_FILE" != "$SCRIPT_DIR/.env" ]; then
    if [ -e "$SCRIPT_DIR/.env" ] && [ ! -L "$SCRIPT_DIR/.env" ]; then
        BACKUP_FILE="$SCRIPT_DIR/.env.backup.$(date +%Y%m%d_%H%M%S)"
        cp -p "$SCRIPT_DIR/.env" "$BACKUP_FILE"
        echo "⚠️  现有 .env 已备份为: $(basename "$BACKUP_FILE")"
    fi
    ln -sf "$ENV_FILE" "$SCRIPT_DIR/.env"
    echo "🔗 已链接 $ENV_FILE -> .env"
fi

# 检查凭证文件（如果配置了 KIRO_CREDS_FILE）
CREDS_FILE=$(grep "^KIRO_CREDS_FILE=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"')
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
        echo "   🔑 API Key: $(grep "^PROXY_API_KEY=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"')"
        echo "   📋 模型列表: curl -H \"Authorization: Bearer \$(grep ^PROXY_API_KEY= $ENV_FILE | cut -d'=' -f2 | tr -d '\"')\" http://localhost:8000/v1/models"
        echo "   📜 查看日志: docker-compose logs -f"
        exit 0
    fi
    sleep 1
done

echo "❌ 服务启动超时，请查看日志: docker-compose logs -f"
exit 1
