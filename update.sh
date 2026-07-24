#!/usr/bin/env bash
# ============================================================
# leads-background 一键更新脚本（带版本检查 + 静默模式）
# 先比对本地与远端字节数，已是最新则跳过，有新版本才覆盖
# 用法:
#   bash update.sh           普通模式（显示所有信息）
#   bash update.sh -q        静默模式（仅真更新时才输出）
# ============================================================
set -uo pipefail

QUIET=0
for arg in "$@"; do
  case "$arg" in
    -q|--quiet) QUIET=1 ;;
  esac
done

info() { if [ "$QUIET" -eq 0 ]; then echo "$@"; fi; }

REPO="DennisTOS/leads-background"
BRANCH="main"
BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
API="https://api.github.com/repos/${REPO}/contents"
TARGET_DIR="$HOME/.workbuddy/skills/leads-background"

info "📦 leads-background 更新脚本"
info "   源仓库: ${REPO} (${BRANCH})"

mkdir -p "$TARGET_DIR"

# 取远端文件字节大小：优先 raw Content-Length，失败回退 GitHub API
remote_size() {
  local f="$1"
  local sz=""
  sz=$(curl -fsSL --http1.1 -I "${BASE}/${f}" 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="content-length"{print $2}' | head -1) || true
  if [ -z "$sz" ]; then
    sz=$(curl -fsSL --http1.1 "${API}/${f}" 2>/dev/null | grep -oE '"size": ?[0-9]+' | head -1 | grep -oE '[0-9]+') || true
  fi
  echo "$sz"
}

FILES=(SKILL.md README.md)
CHANGED=0
for f in "${FILES[@]}"; do
  local_path="$TARGET_DIR/$f"
  old_size=0
  if [ -f "$local_path" ]; then
    old_size=$(wc -c < "$local_path" | tr -d ' ')
  fi

  rsize=$(remote_size "$f")
  if [ -n "$rsize" ] && [ "$old_size" = "$rsize" ]; then
    info "✅ $f 已是最新 (${old_size} 字节)，跳过"
    continue
  fi

  echo ""
  echo "⬇️  更新 $f (本地 ${old_size} → 远端 ${rsize:-未知} 字节)..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --http1.1 -o "$local_path" "${BASE}/${f}"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$local_path" "${BASE}/${f}"
  else
    echo "❌ 未找到 curl 或 wget，无法下载" >&2
    exit 1
  fi

  new_size=$(wc -c < "$local_path" | tr -d ' ')
  if [ "$new_size" -lt 100 ]; then
    echo "⚠️  下载文件异常小 (${new_size} 字节)，可能网络受限，请检查后重试" >&2
    exit 1
  fi
  echo "✅ $f 已更新 -> ${new_size} 字节"
  CHANGED=1
done

echo ""
if [ "$CHANGED" -eq 0 ]; then
  info "🎉 全部已是最新，无需更新！"
else
  echo "🎉 更新完成！重启 WorkBuddy 对话即可加载新版本。"
fi
echo "📍 路径: $TARGET_DIR"
