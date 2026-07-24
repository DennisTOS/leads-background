#!/usr/bin/env bash
# ============================================================
# leads-background 一键更新脚本
# 从 GitHub 拉取最新 SKILL.md / README.md，覆盖本地副本
# 用法: bash update.sh
# ============================================================
set -euo pipefail

REPO="DennisTOS/leads-background"
BRANCH="main"
BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
TARGET_DIR="$HOME/.workbuddy/skills/leads-background"

echo "📦 leads-background 更新脚本"
echo "   源仓库: ${REPO} (${BRANCH})"

mkdir -p "$TARGET_DIR"

FILES=(SKILL.md README.md)
for f in "${FILES[@]}"; do
  local_path="$TARGET_DIR/$f"
  remote="$BASE/$f"

  old_size=0
  if [ -f "$local_path" ]; then
    old_size=$(wc -c < "$local_path" | tr -d ' ')
  fi

  echo ""
  echo "⬇️  更新 $f (本地 ${old_size} 字节)..."

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --http1.1 -o "$local_path" "$remote"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$local_path" "$remote"
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
done

echo ""
echo "🎉 全部完成！重启 WorkBuddy 对话即可加载新版本。"
echo "📍 路径: $TARGET_DIR"
