#!/usr/bin/env bash
# Validate the marketplace manifest and every plugin in the repo using the
# official `claude plugin validate` command. Exits non-zero if any validation
# fails. Used by CI; also safe to run locally before committing.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v claude >/dev/null 2>&1; then
  echo "✘ \`claude\` CLI not found on PATH. Install Claude Code first." >&2
  exit 127
fi

failed=0

echo "→ marketplace (.)"
claude plugin validate . || failed=1

# Each top-level subdir with .claude-plugin/plugin.json is a plugin.
for plugin_json in */.claude-plugin/plugin.json; do
  plugin_dir=$(dirname "$(dirname "$plugin_json")")
  echo
  echo "→ plugin: $plugin_dir"
  claude plugin validate "$plugin_dir" || failed=1
done

echo
if [ "$failed" -ne 0 ]; then
  echo "✘ One or more validations failed."
  exit 1
fi
echo "✓ All validations passed."
