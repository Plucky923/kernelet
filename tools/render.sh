#!/usr/bin/env bash
# Render a built page with a headless Chrome, for changes that touch how a page looks.
#
#   tools/render.sh PAGE [OUT.png]     screenshot book/PAGE to OUT.png (default .cache/render/…png)
#                                      and check that every Mermaid block on the page was rendered
#   tools/render.sh --install          fetch a headless Chrome into .cache/puppeteer and stop
#
# The browser is looked for in this order: $CHROME, the project cache (.cache/puppeteer), the
# user's Puppeteer cache (~/.cache/puppeteer), then chromium / google-chrome on PATH. If none is
# found, one is fetched into the project cache with `npx @puppeteer/browsers`, which needs Node.js.
# Nothing is installed outside the repository.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cache="$root/.cache/puppeteer"

find_browser() {
    if [ -n "${CHROME:-}" ] && [ -x "$CHROME" ]; then echo "$CHROME"; return 0; fi
    local dir b
    for dir in "$cache" "$HOME/.cache/puppeteer"; do
        for b in "$dir"/chrome-headless-shell/*/chrome-headless-shell-*/chrome-headless-shell \
                 "$dir"/chrome/*/chrome-*/chrome; do
            if [ -x "$b" ]; then echo "$b"; return 0; fi
        done
    done
    for b in chromium chromium-browser google-chrome google-chrome-stable; do
        if command -v "$b" >/dev/null 2>&1; then command -v "$b"; return 0; fi
    done
    return 1
}

install_browser() {
    if ! command -v npx >/dev/null 2>&1; then
        echo "render: no browser found and no npx to fetch one; install Node.js or set CHROME=/path/to/chrome" >&2
        exit 2
    fi
    echo "render: fetching chrome-headless-shell into $cache (one-time, about 150 MB)" >&2
    npx --yes @puppeteer/browsers install chrome-headless-shell@stable --path "$cache" >&2
}

if [ "${1:-}" = "--install" ]; then
    install_browser
    find_browser
    exit 0
fi

page=${1:-}
if [ -z "$page" ]; then
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
fi
html="$root/book/$page"
if [ ! -f "$html" ]; then
    echo "render: $html does not exist; run 'make build' first" >&2
    exit 2
fi
out=${2:-"$root/.cache/render/$(echo "$page" | tr '/' '-' | sed 's/\.html$//').png"}
mkdir -p "$(dirname "$out")"

browser=$(find_browser) || { install_browser; browser=$(find_browser); }
flags=(--headless --no-sandbox --disable-gpu --hide-scrollbars --virtual-time-budget=5000 --window-size=1400,2000)

"$browser" "${flags[@]}" "--screenshot=$out" "file://$html" 2>/dev/null
dom=$("$browser" "${flags[@]}" --dump-dom "file://$html" 2>/dev/null)
blocks=$(grep -o '<pre class="mermaid"' <<<"$dom" | wc -l || true)
rendered=$(grep -o '<pre class="mermaid" data-processed="true"><svg' <<<"$dom" | wc -l || true)

echo "render: $out"
echo "render: mermaid blocks $rendered/$blocks rendered"
if [ "$blocks" -ne "$rendered" ]; then
    echo "render: FAILED: a Mermaid block on $page did not render" >&2
    exit 1
fi
