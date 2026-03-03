#!/bin/bash
# fetch_libs.sh – Download embedded libraries for local development.
#
# In production, .pkgmeta handles this via the CurseForge packager.
# This script fetches everything needed for local testing.
#
# Libraries from GitHub:
#   - LibStub           (https://github.com/lua-wow/LibStub)
#   - Ace3 Framework    (https://github.com/WoWUIDev/Ace3)
#   - LibDataBroker-1.1 (https://github.com/tekkub/libdatabroker-1-1)
#
# Libraries from CurseForge/WowAce (no GitHub repo):
#   - LibSharedMedia-3.0 (https://www.curseforge.com/wow/addons/libsharedmedia-3-0)
#   - LibDBIcon-1.0      (https://www.curseforge.com/wow/addons/libdbicon-1-0)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBS_DIR="$SCRIPT_DIR/Libs"
TMP_DIR=$(mktemp -d)

trap "rm -rf $TMP_DIR" EXIT

echo "=== Epic Damage Meter V2 – Library Fetcher ==="
echo ""

# --- LibStub ---
if [ ! -f "$LIBS_DIR/LibStub/LibStub.lua" ]; then
    echo "[1/5] Downloading LibStub..."
    git clone --depth 1 https://github.com/lua-wow/LibStub.git "$TMP_DIR/LibStub"
    mkdir -p "$LIBS_DIR/LibStub"
    cp "$TMP_DIR/LibStub/LibStub.lua" "$LIBS_DIR/LibStub/"
else
    echo "[1/5] LibStub already present, skipping."
fi

# --- Ace3 (CallbackHandler, AceAddon, AceDB, AceEvent, AceConsole) ---
ACE3_LIBS="CallbackHandler-1.0 AceAddon-3.0 AceDB-3.0 AceEvent-3.0 AceConsole-3.0"
NEED_ACE3=false
for lib in $ACE3_LIBS; do
    if [ ! -d "$LIBS_DIR/$lib" ]; then
        NEED_ACE3=true
        break
    fi
done

if [ "$NEED_ACE3" = true ]; then
    echo "[2/5] Downloading Ace3 Framework..."
    git clone --depth 1 https://github.com/WoWUIDev/Ace3.git "$TMP_DIR/Ace3"
    for lib in $ACE3_LIBS; do
        if [ ! -d "$LIBS_DIR/$lib" ]; then
            cp -r "$TMP_DIR/Ace3/$lib" "$LIBS_DIR/$lib"
            echo "      + $lib"
        fi
    done
else
    echo "[2/5] Ace3 libraries already present, skipping."
fi

# --- LibDataBroker-1.1 ---
if [ ! -f "$LIBS_DIR/LibDataBroker-1.1/LibDataBroker-1.1.lua" ]; then
    echo "[3/5] Downloading LibDataBroker-1.1..."
    git clone --depth 1 https://github.com/tekkub/libdatabroker-1-1.git "$TMP_DIR/LDB"
    mkdir -p "$LIBS_DIR/LibDataBroker-1.1"
    cp "$TMP_DIR/LDB/LibDataBroker-1.1.lua" "$LIBS_DIR/LibDataBroker-1.1/"
else
    echo "[3/5] LibDataBroker-1.1 already present, skipping."
fi

# --- LibSharedMedia-3.0 (no GitHub) ---
if [ ! -f "$LIBS_DIR/LibSharedMedia-3.0/LibSharedMedia-3.0.lua" ]; then
    echo "[4/5] LibSharedMedia-3.0 – NOT AVAILABLE VIA GIT"
    echo "      Download from: https://www.curseforge.com/wow/addons/libsharedmedia-3-0"
    echo "      Extract LibSharedMedia-3.0/ folder into: $LIBS_DIR/LibSharedMedia-3.0/"
    echo "      Then add to embeds.xml:"
    echo '      <Include file="LibSharedMedia-3.0\lib.xml"/>'
else
    echo "[4/5] LibSharedMedia-3.0 already present."
fi

# --- LibDBIcon-1.0 (no GitHub) ---
if [ ! -f "$LIBS_DIR/LibDBIcon-1.0/LibDBIcon-1.0.lua" ]; then
    echo "[5/5] LibDBIcon-1.0 – NOT AVAILABLE VIA GIT"
    echo "      Download from: https://www.curseforge.com/wow/addons/libdbicon-1-0"
    echo "      Extract LibDBIcon-1.0/ folder into: $LIBS_DIR/LibDBIcon-1.0/"
    echo "      Then add to embeds.xml:"
    echo '      <Include file="LibDBIcon-1.0\lib.xml"/>'
else
    echo "[5/5] LibDBIcon-1.0 already present."
fi

echo ""
echo "=== Done ==="
echo ""
echo "Note: LibSharedMedia-3.0 and LibDBIcon-1.0 are optional."
echo "The addon works without them. They are auto-fetched by"
echo "the CurseForge packager via .pkgmeta when you publish."
