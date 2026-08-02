#!/usr/bin/env bash
# ============================================================
# leads-background 一键更新脚本（带版本检查 + 静默模式 + 多 Agent 支持）
# 先比对本地与远端字节数，已是最新则跳过，有新版本才覆盖
# 主源（raw.githubusercontent.com）失败时自动回退多个 GitHub Proxy 镜像
# 用法:
#   bash update.sh                    更新所有已安装 Agent 的 skill 目录
#   bash update.sh -q                 静默模式（仅真更新时才输出）
#   bash update.sh codex              只更新指定 Agent（workbuddy/codex/claude/cursor）
#   bash update.sh --dir /自定义路径   更新自定义目录
# ============================================================
set -uo pipefail

QUIET=0
TARGETS=()

info() { if [ "$QUIET" -eq 0 ]; then echo "$@"; fi; }

REPO="DennisTOS/leads-background"
BRANCH="main"
BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
API="https://api.github.com/repos/${REPO}/contents"

# 已知 Agent 的 skill 目录（只更新实际存在的；新 Agent 在此加一行即可）
# 注意：兼容 macOS 自带 bash 3.2，不使用关联数组，用两个平行数组
AGENT_NAMES=(workbuddy codex claude cursor)
AGENT_DIRS=(
  "$HOME/.workbuddy/skills/leads-background"
  "$HOME/.codex/skills/leads-background"
  "$HOME/.claude/skills/leads-background"
  "$HOME/.cursor/skills/leads-background"
)

# 按 Agent 名解析目录；找不到返回 1
resolve_agent_dir() {
  local name="$1" i
  for i in "${!AGENT_NAMES[@]}"; do
    if [ "${AGENT_NAMES[$i]}" = "$name" ]; then
      echo "${AGENT_DIRS[$i]}"
      return 0
    fi
  done
  return 1
}

# 解析参数：-q/--quiet | --dir <path> | <agent 名>
ARGS=("$@")
i=0
while [ "$i" -lt "${#ARGS[@]}" ]; do
  a="${ARGS[$i]}"
  case "$a" in
    -q|--quiet) QUIET=1 ;;
    --dir)
      i=$((i+1))
      if [ "$i" -lt "${#ARGS[@]}" ]; then TARGETS+=("${ARGS[$i]}"); fi
      ;;
    *)
      d=$(resolve_agent_dir "$a")
      if [ -n "$d" ]; then
        TARGETS+=("$d")
      else
        echo "⚠️  未知 Agent: $a（可用: ${AGENT_NAMES[*]}）" >&2
      fi
      ;;
  esac
  i=$((i+1))
done

# 无参数：自动收集所有已安装 Agent 的目录；一个都没有时回退 workbuddy
if [ "${#TARGETS[@]}" -eq 0 ]; then
  for i in "${!AGENT_NAMES[@]}"; do
    d="${AGENT_DIRS[$i]}"
    if [ -d "$d" ]; then TARGETS+=("$d"); fi
  done
  if [ "${#TARGETS[@]}" -eq 0 ]; then
    TARGETS+=("${AGENT_DIRS[0]}")
  fi
fi

# 下载候选源：主源 + 多个 GitHub Proxy 镜像（主源失败时依次回退）
CANDIDATE_BASES=("$BASE" "https://ghproxy.com/${BASE}" "https://ghproxy.net/${BASE}" "https://mirror.ghproxy.com/${BASE}")

# 自动检测本地代理（中国大陆网络常用）：优先读 git 代理配置，其次探测常见端口
detect_proxy() {
  local p=""
  p=$(git config --global --get http.proxy 2>/dev/null)
  if [ -n "$p" ]; then echo "$p"; return 0; fi
  for port in 7890 7897 10809 1080 8080; do
    if curl -s -o /dev/null --connect-timeout 2 -x "http://127.0.0.1:${port}" "http://www.gstatic.com/generate_204" 2>/dev/null; then
      echo "http://127.0.0.1:${port}"
      return 0
    fi
  done
  return 1
}

PROXY=""
if command -v curl >/dev/null 2>&1; then
  PROXY=$(detect_proxy) || true
fi
CURL_EXTRA=""
if [ -n "$PROXY" ]; then
  CURL_EXTRA="-x $PROXY"
  export http_proxy="$PROXY" https_proxy="$PROXY"
  info "   已检测到本地代理: $PROXY"
fi

info "📦 leads-background 更新脚本"
info "   源仓库: ${REPO} (${BRANCH})"
info "   目标目录: ${TARGETS[*]}"

# 取远端文件字节大小：优先 raw Content-Length，失败回退 GitHub API
remote_size() {
  local f="$1"
  local sz=""
  sz=$(curl -fsSL --http1.1 $CURL_EXTRA -I "${BASE}/${f}" 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="content-length"{print $2}' | head -1) || true
  if [ -z "$sz" ]; then
    sz=$(curl -fsSL --http1.1 $CURL_EXTRA "${API}/${f}" 2>/dev/null | grep -oE '"size": ?[0-9]+' | head -1 | grep -oE '[0-9]+') || true
  fi
  echo "$sz"
}

FILES=(SKILL.md README.md update.sh update.ps1)

# 更新单个目录，返回该目录是否有文件变更（0=无变更 1=有变更）
update_dir() {
  local TARGET_DIR="$1"
  local changed=0
  mkdir -p "$TARGET_DIR"

  for f in "${FILES[@]}"; do
    local local_path="$TARGET_DIR/$f"
    local old_size=0
    if [ -f "$local_path" ]; then
      old_size=$(wc -c < "$local_path" | tr -d ' ')
    fi

    local rsize
    rsize=$(remote_size "$f")
    if [ -n "$rsize" ] && [ "$old_size" = "$rsize" ]; then
      info "  ✅ $f 已是最新 (${old_size} 字节)，跳过"
      continue
    fi

    echo "  ⬇️  更新 $f (本地 ${old_size} → 远端 ${rsize:-未知} 字节)..."
    local dl_ok=0
    for cb in "${CANDIDATE_BASES[@]}"; do
      if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --http1.1 $CURL_EXTRA -o "$local_path" "${cb}/${f}" 2>/dev/null; then dl_ok=1; break; fi
      elif command -v wget >/dev/null 2>&1; then
        if wget -q -O "$local_path" "${cb}/${f}" 2>/dev/null; then dl_ok=1; break; fi
      else
        echo "  ❌ 未找到 curl 或 wget，无法下载" >&2
        return 2
      fi
    done
    if [ "$dl_ok" -ne 1 ]; then
      echo "  ❌ 所有源（含 GitHub Proxy 镜像）均下载失败，请检查网络后重试" >&2
      return 2
    fi

    local new_size
    new_size=$(wc -c < "$local_path" | tr -d ' ')
    if [ "$new_size" -lt 100 ]; then
      echo "  ⚠️  下载文件异常小 (${new_size} 字节)，可能网络受限，请检查后重试" >&2
      return 2
    fi
    echo "  ✅ $f 已更新 -> ${new_size} 字节"
    changed=1
  done

  if [ "$changed" -eq 1 ]; then
    echo "📍 $TARGET_DIR 已更新，重启对应 Agent 对话即可加载新版本。"
  else
    info "📍 $TARGET_DIR 全部已是最新。"
  fi
  return 0
}

OVERALL=0
for t in "${TARGETS[@]}"; do
  echo ""
  echo "==> $t"
  update_dir "$t"
  rc=$?
  if [ "$rc" -eq 1 ]; then OVERALL=1; fi
  if [ "$rc" -eq 2 ]; then exit 2; fi
done

echo ""
if [ "$OVERALL" -eq 0 ]; then
  info "🎉 全部已是最新，无需更新！"
fi
