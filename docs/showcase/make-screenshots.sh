#!/bin/sh
# Regenerates docs/showcase/diff.png from the generic sample files in
# docs/showcase/sample/. Needs: bin/bend-semver-checks (just build), jq, and a
# headless Chrome/Chromium (CHROME=/path overrides the macOS default).
set -eu
cd "$(dirname "$0")/../.."
CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
bin=bin/bend-semver-checks
old=docs/showcase/sample/LAWS.old.bend
new=docs/showcase/sample/LAWS.new.bend
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

set +e
$bin diff "$old" "$new" > "$tmp/out.json"
rc=$?
set -e

summary=$(jq -r '"breaking: \(.breaking)   removed \(.summary.removed)  changed \(.summary.changed)  added \(.summary.added)  unchanged \(.summary.unchanged)"' "$tmp/out.json")
detail=$(jq -r '
  (.removed[] | "- removed   \(.name)   \(.statement)"),
  (.changed[] | "~ \(.kind)  \(.name)   binders \(.old.binders|length) -> \(.new.binders|length)"),
  (.added[]   | "+ added     \(.name)   \(.statement)")' "$tmp/out.json")

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
{
  echo '<html><body style="margin:0;background:#1e1e2e"><pre style="margin:0;padding:22px 26px;color:#cdd6f4;font:15px/1.5 Menlo,monospace;width:860px">'
  printf '$ bend-semver-checks diff LAWS.old.bend LAWS.new.bend\n' | esc
  printf '%s\n\n%s\n' "$summary" "$detail" | esc
  printf '\n$ echo $?\n%s\n' "$rc" | esc
  echo '</pre></body></html>'
} > "$tmp/page.html"

"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=910,300 --screenshot="$PWD/docs/showcase/diff.png" "file://$tmp/page.html" >/dev/null 2>&1
echo "wrote docs/showcase/diff.png ($(wc -c < docs/showcase/diff.png) bytes)"
