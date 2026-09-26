#!/usr/bin/env bash
# Fails when shipping app code contains placeholder, unfinished or fake content.
# Runs in both CI workflows. Tests, docs and *.example templates are excluded.
set -euo pipefail
cd "$(dirname "$0")/.."

PATTERN='lorem|ipsum|\bTODO\b|\bFIXME\b|\bXXX\b|\bHACK\b|coming soon|\bdummy\b|\bscaffold(ing)?\b|REPLACE_ME|\bTBD\b|placeholder text|sample data|fake (data|user|name|account)|john doe|jane doe|example\.com|under construction|not (yet )?implemented|add google-services\.json'

set +e
HITS=$(grep -RInE -i "$PATTERN" App Android/app/src/main \
  --include='*.swift' --include='*.kt' --include='*.java' --include='*.xml' --include='*.plist' \
  --include='*.strings' --include='*.json' --include='*.html' \
  --exclude='*.example' \
  | grep -vE 'material3\.Scaffold|\bScaffold\(' )
set -e

if [ -n "$HITS" ]; then
  echo "::error::Placeholder or unfinished content found in app sources:"
  echo "$HITS"
  echo
  echo "Replace it with real content or remove the feature before merging."
  exit 1
fi
echo "Placeholder check passed: no placeholder content in App/ or Android/app/src/main."
