#!/bin/bash
# Kiro Gateway - 停止脚本
# 用法: ./stop.sh [名称 | --env <文件路径>] [--project <名称>] | --all

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 解析参数
ENV_FILE=""
PROJECT_NAME=""
STOP_ALL=false
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
        --all|-a)
            STOP_ALL=true
            shift
            ;;
        --help|-h)
            echo "用法: $0 [名称 | --env <文件路径>] [--project <名称>] | --all"
            echo ""
            echo "简写:"
            echo "  $0 zzk                 # 停止 zzk 实例"
            echo ""
            echo "选项:"
            echo "  --env, -e <path>     指定 env 文件（与 start.sh 一致）"
            echo "  --project, -p <name> 指定项目名"
            echo "  --name, -n <name>    同 --project"
            echo "  --all, -a            停止所有 kiro-gateway 实例"
            echo "  --help, -h           显示帮助"
            echo ""
            echo "示例:"
            echo "  $0 zzk"
            echo "  $0 --env envs/zzk/zzk.env"
            echo "  $0 --all"
            exit 0
            ;;
        -*)
            echo "❌ 未知参数: $1"
            echo "运行 $0 --help 查看帮助"
            exit 1
            ;;
        *)
            # 简写: 第一个位置参数当作名称
            if [ -z "$ENV_FILE" ]; then
                if [ -f "$SCRIPT_DIR/envs/$1/$1.env" ]; then
                    ENV_FILE="$SCRIPT_DIR/envs/$1/$1.env"
                    [ -z "$PROJECT_NAME" ] && PROJECT_NAME="$1"
                else
                    PROJECT_NAME="$1"
                fi
            else
                echo "❌ 多次指定参数: $1"
                exit 1
            fi
            # 点开头的名字（.env 等）不合法，映射为 default
            if [[ "$PROJECT_NAME" == .* ]]; then
                PROJECT_NAME="default"
            fi
            shift
            ;;
    esac
done

# 停止所有实例
if [ "$STOP_ALL" = true ]; then
    echo "🛑 停止所有 kiro-gateway 实例..."
    # 先尝试用 docker-compose down 清理所有有 override 文件的项目
    for override in "$SCRIPT_DIR"/.docker-compose.override.*.yml; do
        [ -f "$override" ] || continue
        project=$(basename "$override" .yml | sed 's/^\.docker-compose\.override\.//')
        # 跳过以点开头的（历史残留），避免 kiro-gateway-.env 这种非法项目名
        [[ "$project" == .* ]] && continue
        echo "  - $project"
        docker-compose -p "kiro-gateway-${project}" -f docker-compose.yml -f "$override" down 2>/dev/null || true
        rm -f "$override"
    done
    # 兜底: 直接停掉所有 kiro-gateway 容器
    for container in $(docker ps -a --format '{{.Names}}' | grep -E 'kiro-gateway' || true); do
        echo "  - 兜底停止 $container"
        docker stop "$container" > /dev/null 2>&1 || true
        docker rm "$container" > /dev/null 2>&1 || true
    done
    # 清理残留网络
    for net in $(docker network ls --format '{{.Name}}' | grep -E 'kiro|gateway' || true); do
        docker network rm "$net" > /dev/null 2>&1 || true
    done
    echo "✅ 已停止所有实例"
    exit 0
fi

# 单实例停止
if [ -z "$PROJECT_NAME" ] && [ -z "$ENV_FILE" ]; then
    echo "❌ 请指定要停止的实例，或用 --all 停止所有"
    echo "   示例: $0 zzk   或   $0 --all"
    exit 1
fi

# 自动从 env 文件推导项目名
if [ -n "$ENV_FILE" ] && [ -z "$PROJECT_NAME" ]; then
    if [[ "$ENV_FILE" != /* ]]; then
        ENV_FILE="$SCRIPT_DIR/$ENV_FILE"
    fi
    # 默认 .env 会得到点开头的 "env"，不合法。统一处理为 "default"
    RAW_NAME=$(basename "$ENV_FILE" .env)
    if [ -z "$RAW_NAME" ] || [ "$RAW_NAME" = "." ] || [[ "$RAW_NAME" == .* ]]; then
        PROJECT_NAME="default"
    else
        PROJECT_NAME="$RAW_NAME"
    fi
fi

echo "🛑 停止实例: $PROJECT_NAME"

# 找到或重建 override 文件
OVERRIDE_FILE="$SCRIPT_DIR/.docker-compose.override.${PROJECT_NAME}.yml"
if [ ! -f "$OVERRIDE_FILE" ] && [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
    cat > "$OVERRIDE_FILE" <<EOF
services:
  kiro-gateway:
    env_file:
      - $ENV_FILE
EOF
fi

COMPOSE_FILES=("-f" "docker-compose.yml")
if [ -f "$OVERRIDE_FILE" ]; then
    COMPOSE_FILES+=("-f" "$OVERRIDE_FILE")
fi

docker-compose -p "kiro-gateway-${PROJECT_NAME}" "${COMPOSE_FILES[@]}" down

# 跑完 down 后清理 override 文件
rm -f "$OVERRIDE_FILE"

echo "✅ 已停止 $PROJECT_NAME"
