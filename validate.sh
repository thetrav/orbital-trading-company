#!/usr/bin/env bash
set -uo pipefail

MOD_DIR="$(cd "$(dirname "$0")" && pwd)"
FACTORIO_BIN="$HOME/.local/share/Steam/steamapps/common/Factorio/bin/x64/factorio"
FACTORIO_MODS="$HOME/.factorio/mods"
BUSTED="${BUSTED:-$HOME/.luarocks/bin/busted}"
TMP_MAP="/tmp/otc-validate-$$"
RC=0

echo "=== 1/6 luacheck ==="
luacheck "$MOD_DIR/scripts/" "$MOD_DIR/control.lua" "$MOD_DIR/data.lua"; ec=$?
if [ "$ec" -eq 2 ]; then RC=1; fi
echo ""

echo "=== 2/6 lua-language-server type check ==="
# Performs full workspace diagnosis using .luarc.json config
lua-language-server --check="$MOD_DIR" --check_format=pretty --metapath="$HOME/.cache/lua-language-server/meta" 2>&1; ec=$?
if [ "$ec" -ne 0 ]; then RC=1; fi
echo ""

echo "=== 3/6 busted unit tests ==="
if [ -x "$BUSTED" ]; then
    if (cd "$MOD_DIR" && "$BUSTED"); then
        echo "OK"
    else
        RC=1
    fi
else
    echo "SKIPPED: busted not found at $BUSTED (luarocks install --local busted)" >&2
fi
echo ""

echo "=== 4/6 headless --dump-data (prototype validation) ==="
if "$FACTORIO_BIN" --mod-directory "$FACTORIO_MODS" --dump-data 2>&1; then
    echo "OK"
else
    RC=1
fi
echo ""

echo "=== 5/6 headless --create (save creation) ==="
if "$FACTORIO_BIN" --create "$TMP_MAP" --mod-directory "$FACTORIO_MODS" 2>&1; then
    echo "OK"
else
    RC=1
fi
echo ""

echo "=== 6/6 headless --load-game --until-tick 600 (runtime smoke test) ==="
if "$FACTORIO_BIN" --load-game "$TMP_MAP" --mod-directory "$FACTORIO_MODS" --until-tick 600 2>&1; then
    echo "OK"
else
    RC=1
fi
rm -f "$TMP_MAP"
echo ""

if [ "$RC" -eq 0 ]; then
    echo "=== ALL 6 CHECKS PASSED ==="
else
    echo "=== SOME CHECKS FAILED ===" >&2
fi
exit "$RC"
