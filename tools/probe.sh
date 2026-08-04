#!/usr/bin/env bash
# Run a throwaway probe module inside headless Factorio and print what it logs.
#
#   tools/probe.sh tools/probes/drills.lua              # working tree
#   tools/probe.sh tools/probes/drills.lua --ref HEAD   # a git ref, to A/B a change
#   tools/probe.sh tools/probes/drills.lua --ticks 600  # also load and run N ticks
#
# The probe module must return a table with a `run()` function; it is called at
# the end of on_init. It may also register its own events at require time.
# Anything it log()s containing PROBE is printed.
#
# Nothing in the repo is touched: the mod is staged into a temp directory and the
# probe is injected there.

set -uo pipefail

MOD_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MOD_NAME="orbital-trading-company"
FACTORIO_BIN="$HOME/.local/share/Steam/steamapps/common/Factorio/bin/x64/factorio"

PROBE=""
REF=""
TICKS=0

while [ $# -gt 0 ]; do
    case "$1" in
        --ref)   REF="$2"; shift 2 ;;
        --ticks) TICKS="$2"; shift 2 ;;
        *)       PROBE="$1"; shift ;;
    esac
done

if [ -z "$PROBE" ] || [ ! -f "$PROBE" ]; then
    echo "usage: tools/probe.sh <probe.lua> [--ref <git-ref>] [--ticks <n>]" >&2
    exit 2
fi

STAGE="$(mktemp -d /tmp/otc-probe-XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
STAGED_MOD="$STAGE/mods/$MOD_NAME"
mkdir -p "$STAGED_MOD"

if [ -n "$REF" ]; then
    echo "--- staging $MOD_NAME at $REF"
    git -C "$MOD_DIR" archive "$REF" | tar -x -C "$STAGED_MOD" || exit 1
else
    echo "--- staging $MOD_NAME from the working tree"
    git -C "$MOD_DIR" ls-files -co --exclude-standard \
        | while IFS= read -r f; do
            mkdir -p "$STAGED_MOD/$(dirname "$f")"
            cp "$MOD_DIR/$f" "$STAGED_MOD/$f"
        done
fi

cp "$HOME/.factorio/mods/mod-list.json" "$STAGE/mods/mod-list.json"
cp "$PROBE" "$STAGED_MOD/scripts/otc_probe.lua"

# Inject the probe into the staged copy: require it alongside the other modules,
# and call run() once the world has been built.
CONTROL="$STAGED_MOD/control.lua"
{
    echo 'local otc_probe = require("scripts.otc_probe")'
    cat "$CONTROL"
} > "$CONTROL.tmp" && mv "$CONTROL.tmp" "$CONTROL"

awk '
    { print }
    !done && /^    nauvis_industry\.ensure_built\(\)$/ { print "    otc_probe.run()"; done = 1 }
' "$CONTROL" > "$CONTROL.tmp" && mv "$CONTROL.tmp" "$CONTROL"

if ! grep -q "otc_probe.run()" "$CONTROL"; then
    echo "could not find the on_init hook to inject into" >&2
    exit 1
fi

# A crash prints its stack trace on the lines after the "Error while running"
# line, which the filter throws away. PROBE_VERBOSE=1 keeps everything.
filter() {
    if [ -n "${PROBE_VERBOSE:-}" ]; then
        cat
    else
        grep -E "PROBE|Error|error while running" | sed 's/^.*otc_probe\.lua:[0-9]*: //'
    fi
}

MAP="$STAGE/map"
echo "--- create"
"$FACTORIO_BIN" --create "$MAP" --mod-directory "$STAGE/mods" 2>&1 | filter

if [ "$TICKS" -gt 0 ]; then
    echo "--- run $TICKS ticks"
    "$FACTORIO_BIN" --load-game "$MAP" --mod-directory "$STAGE/mods" --until-tick "$TICKS" 2>&1 | filter
fi
