#!/usr/bin/env bash
# Install the `nscc` skill for Claude Code and/or Codex by copying it into their skill folders.
#   ./install.sh            both
#   ./install.sh claude     Claude Code only  (~/.claude/skills/nscc)
#   ./install.sh codex      Codex only        (~/.agents/skills/nscc)
# Without a clone:  curl -fsSL https://raw.githubusercontent.com/LBWSquare666/nscc-agent/main/install.sh | bash
set -euo pipefail

REPO="https://github.com/LBWSquare666/nscc-agent"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || here=""
src="$here/plugins/nscc-agent/skills/nscc"
if [[ ! -f "$src/SKILL.md" ]]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  git clone -q --depth 1 "$REPO" "$tmp/nscc-agent"
  src="$tmp/nscc-agent/plugins/nscc-agent/skills/nscc"
fi

install_to() {
  rm -rf "$1/nscc"; mkdir -p "$1"; cp -R "$src" "$1/nscc"; chmod +x "$1/nscc/scripts/nscc.sh"
  echo "installed: $1/nscc"
}
case "${1:-all}" in
  claude) install_to "$HOME/.claude/skills" ;;
  codex)  install_to "$HOME/.agents/skills" ;;
  all)    install_to "$HOME/.claude/skills"; install_to "$HOME/.agents/skills" ;;
  *)      echo "usage: install.sh [claude|codex|all]" >&2; exit 64 ;;
esac
echo "Next: tell your agent \"connect to NSCC\" (Claude Code: /nscc, Codex: \$nscc)."
