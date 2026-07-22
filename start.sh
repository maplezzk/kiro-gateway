#!/bin/bash
# Kiro Gateway - 启动脚本
# 用法: ./start.sh [名称 | --env <文件路径>] [--project <名称>]

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
            echo "用法: $0 [名称 | --env <文件路径>] [--project <名称>]"
            echo ""
            echo "简写:"
            echo "  $0 <名称>              等价于 envs/<名称>/<名称>.env + project=<名称>"
            echo ""
            echo "选项:"
            echo "  --env, -e <path>       指定配置文件路径（默认: .env）"
            echo "  --project, -p <name>   指定 docker-compose 项目名（默认从配置名推导）"
            echo "  --name, -n <name>      同 --project"
            echo "  --help, -h             显示帮助"
            echo ""
            echo "示例:"
            echo "  $0                     # 使用默认 .env"
            echo "  $0 zzk                 # 使用 envs/zzk/zzk.env"
            echo "  $0 kidd                # 使用 envs/kidd/kidd.env"
            echo "  $0 --env .env.production"
            echo ""
            echo "多实例: 每个实例需要不同的 SERVER_PORT 和不同的项目名"
            exit 0
            ;;
        -*)
            echo "❌ 未知参数: $1"
            echo "运行 $0 --help 查看帮助"
            exit 1
            ;;
        *)
            # 简写: 第一个位置参数优先当作名称
            if [ -z "$ENV_FILE" ]; then
                if [ -f "$SCRIPT_DIR/envs/$1/$1.env" ]; then
                    ENV_FILE="$SCRIPT_DIR/envs/$1/$1.env"
                    [ -z "$PROJECT_NAME" ] && PROJECT_NAME="$1"
                else
                    ENV_FILE="$1"
                fi
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
# 默认 .env 会得到点开头的 "env"，不合法。统一处理为 "default"
if [ -z "$PROJECT_NAME" ]; then
    RAW_NAME=$(basename "$ENV_FILE" .env)
    if [ -z "$RAW_NAME" ] || [ "$RAW_NAME" = "." ] || [[ "$RAW_NAME" == .* ]]; then
        PROJECT_NAME="default"
    else
        PROJECT_NAME="$RAW_NAME"
    fi
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
# 不要用 trap 删除: stop.sh 跑 docker-compose down 时还需要这个文件
OVERRIDE_FILE="$SCRIPT_DIR/.docker-compose.override.${PROJECT_NAME}.yml"
rm -f "$OVERRIDE_FILE"
# 清理历史残留的以点开头的 override 文件（修复 .env 路径 bug 前的产物）
find "$SCRIPT_DIR" -maxdepth 1 -name '.docker-compose.override..*.yml' -delete 2>/dev/null || true
cat > "$OVERRIDE_FILE" <<EOF
services:
  kiro-gateway:
    container_name: kiro-gateway-${PROJECT_NAME}
    env_file:
      - $ENV_FILE
EOF

# 检查凭证文件（如果配置了 KIRO_CREDS_FILE）
CREDS_FILE=$(grep "^KIRO_CREDS_FILE=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"')
if [ -n "$CREDS_FILE" ]; then
    # KIRO_SSO_CACHE_HOST_DIR 是宿主机上的凭证目录，默认 ${HOME}/.aws/sso/cache
    SSO_HOST_DIR=$(grep "^KIRO_SSO_CACHE_HOST_DIR=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"')
    SSO_HOST_DIR="${SSO_HOST_DIR:-$HOME/.aws/sso/cache}"
    # 取容器路径里的文件名，拼到宿主机 SSO 目录后面
    # 不能用 ${VAR/pattern/replace}: bash 只替换第一个匹配，
    # 会留下剩余的 /.aws/sso/cache 段，导致路径重复
    CREDS_FILENAME=$(basename "$CREDS_FILE")
    LOCAL_CREDS="$SSO_HOST_DIR/$CREDS_FILENAME"
    if [ ! -f "$LOCAL_CREDS" ]; then
        echo "❌ 未找到凭证文件: $LOCAL_CREDS"
        echo "   请确认 Kiro IDE 已登录并生成凭证文件"
        echo "   或检查 KIRO_SSO_CACHE_HOST_DIR 是否指向了正确的宿主目录"
        exit 1
    fi
    echo "✅ 凭证文件已找到: $LOCAL_CREDS"
else
    echo "⚠️  未设置 KIRO_CREDS_FILE，容器启动后可能会报 'No Kiro credentials configured'"
    echo "   推荐在 $ENV_FILE 中加入："
    echo "     KIRO_CREDS_FILE=\"/home/kiro/.aws/sso/cache/kiro-auth-token.json\""
    echo "   (搭配 KIRO_SSO_CACHE_HOST_DIR 或默认 ~/.aws/sso/cache)"
fi

# Source env 文件，让 docker-compose.yml 里的 ${VAR:-default} 替换能拿到正确的值
# （不 source 的话，所有变量会 fallback 到默认值，与 env_file 加载的运行时值冲突）
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# 启动容器（指定项目名 + override 文件）
echo "🏗️  构建并启动容器...（每次强制重建镜像以使用最新代码）"
docker-compose -p "kiro-gateway-${PROJECT_NAME}" -f docker-compose.yml -f "$OVERRIDE_FILE" up -d --build

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
        echo "   📜 查看日志: docker-compose -p kiro-gateway-$PROJECT_NAME logs -f"
        exit 0
    fi
    sleep 1
done

echo "❌ 服务启动超时，请查看日志: docker-compose -p kiro-gateway-$PROJECT_NAME logs -f"
exit 1
