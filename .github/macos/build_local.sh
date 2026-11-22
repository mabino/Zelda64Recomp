#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: .github/macos/build_local.sh /path/to/your/majora-mask-rom [build-directory]

Accepts the original US Rev 1 retail ROM (.z64, .n64, or .v64), or its
decompressed form. Builds the recompiler tools, generates the game code,
builds the universal macOS app, and packages a ZIP and DMG.
EOF
}

if [[ $# -lt 1 || $# -gt 2 || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit $(( $# == 1 ? 0 : 2 ))
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This build script runs on macOS." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROM_INPUT="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
BUILD_DIR="${2:-$ROOT/build-macos-local}"
if [[ "$BUILD_DIR" != /* ]]; then
    BUILD_DIR="$ROOT/$BUILD_DIR"
fi

if [[ ! -f "$ROM_INPUT" || ! -r "$ROM_INPUT" ]]; then
    echo "ROM file is missing or unreadable: $ROM_INPUT" >&2
    exit 1
fi

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 1
    fi
}

for command in cmake ninja python3 md5 ditto hdiutil codesign xcrun sysctl; do
    require_command "$command"
done

MACPORTS_PREFIX="${MACPORTS_PREFIX:-/opt/local}"
PATCHES_CC="${PATCHES_CC:-$MACPORTS_PREFIX/bin/clang-mp-18}"
PATCHES_LD="${PATCHES_LD:-$MACPORTS_PREFIX/bin/ld.lld-mp-18}"
PATCHES_AR="${PATCHES_AR:-$MACPORTS_PREFIX/bin/llvm-ar-mp-18}"
for tool in "$PATCHES_CC" "$PATCHES_LD" "$PATCHES_AR"; do
    if [[ ! -x "$tool" ]]; then
        echo "Required MacPorts tool not found: $tool" >&2
        echo "Install clang-18 and llvm-18 with MacPorts; see docs/BUILDING_MACOS.md." >&2
        exit 1
    fi
done

if ! xcrun --find clang >/dev/null 2>&1 || ! xcrun --find clang++ >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are required. Run: xcode-select --install" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR/rom" "$BUILD_DIR/package"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"

# Use the decompressor already included in the checked-out Majora's Mask
# decompilation submodule. It checks the retail and decompressed ROM hashes.
PYTHON_VENV="$BUILD_DIR/python-venv"
if [[ ! -x "$PYTHON_VENV/bin/python" ]]; then
    python3 -m venv "$PYTHON_VENV"
fi
PYTHON="$PYTHON_VENV/bin/python"
if ! "$PYTHON" -c 'import libyaz0, macholib' >/dev/null 2>&1; then
    "$PYTHON" -m pip install --upgrade pip
    "$PYTHON" -m pip install 'libyaz0>=0.5' macholib
fi
export PATH="$PYTHON_VENV/bin:$PATH"

ROM_MD5="$(md5 -q "$ROM_INPUT" | tr '[:upper:]' '[:lower:]')"
DECOMPRESSED_MD5="f46493eaa0628827dbd6ad3ecd8d65d6"
DECOMPRESSED_ROM="$BUILD_DIR/rom/mm.us.rev1.rom_uncompressed.z64"
if [[ "$ROM_MD5" == "$DECOMPRESSED_MD5" ]]; then
    echo "Using the supplied, already-decompressed US Rev 1 ROM."
    cp "$ROM_INPUT" "$DECOMPRESSED_ROM"
else
    ROM_WORK="$(mktemp -d "$BUILD_DIR/rom-work.XXXXXX")"
    ROM_LINK="$ROM_WORK/baserom.mm.us.rev1.z64"
    ln -s "$ROM_INPUT" "$ROM_LINK"
    if ! (cd "$ROM_WORK" && "$PYTHON" "$ROOT/lib/mm-decomp/tools/fixbaserom.py"); then
        rm -rf "$ROM_WORK"
        echo "ROM validation/decompression failed. Supply the US Rev 1 retail ROM or its decompressed form." >&2
        exit 1
    fi
    cp "$ROM_WORK/baserom_uncompressed.z64" "$DECOMPRESSED_ROM"
    rm -rf "$ROM_WORK"
fi

if [[ "$(md5 -q "$DECOMPRESSED_ROM" | tr '[:upper:]' '[:lower:]')" != "$DECOMPRESSED_MD5" ]]; then
    echo "The decompressed ROM checksum is incorrect; stopping before code generation." >&2
    exit 1
fi

echo "Building N64Recomp and RSPRecomp..."
cmake -S "$ROOT/lib/N64ModernRuntime/N64Recomp" -B "$BUILD_DIR/recomp-tools" \
    -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD_DIR/recomp-tools" --target N64Recomp RSPRecomp --parallel "$(sysctl -n hw.ncpu)"
N64_RECOMP="$BUILD_DIR/recomp-tools/N64Recomp"
RSP_RECOMP="$BUILD_DIR/recomp-tools/RSPRecomp"

# The checked-in TOML files refer to the conventional root-level ROM name.
# Make temporary sibling configs so the user's existing files and ROM dumps
# are never replaced by this build helper.
MAIN_CONFIG="$(mktemp "$ROOT/.us.rev1.local.XXXXXX")"
ASP_CONFIG="$(mktemp "$ROOT/.aspMain.us.rev1.local.XXXXXX")"
NJPG_CONFIG="$(mktemp "$ROOT/.njpgdspMain.us.rev1.local.XXXXXX")"
cleanup_configs() {
    rm -f "$MAIN_CONFIG" "$ASP_CONFIG" "$NJPG_CONFIG"
}
trap cleanup_configs EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$PYTHON" - "$ROOT" "$DECOMPRESSED_ROM" "$MAIN_CONFIG" "$ASP_CONFIG" "$NJPG_CONFIG" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
rom = json.dumps(str(pathlib.Path(sys.argv[2]).resolve()))
destinations = sys.argv[3:]
sources = (
    root / "us.rev1.toml",
    root / "aspMain.us.rev1.toml",
    root / "njpgdspMain.us.rev1.toml",
)
for source, config in zip(sources, destinations):
    contents = source.read_text()
    old = 'rom_file_path = "mm.us.rev1.rom_uncompressed.z64"'
    if contents.count(old) != 1:
        raise SystemExit(f"Expected one ROM path in {source}")
    pathlib.Path(config).write_text(contents.replace(old, f"rom_file_path = {rom}"))
PY

echo "Generating game code from the supplied ROM..."
(cd "$ROOT" && "$N64_RECOMP" "$MAIN_CONFIG")
(cd "$ROOT" && "$RSP_RECOMP" "$ASP_CONFIG")
(cd "$ROOT" && "$RSP_RECOMP" "$NJPG_CONFIG")

APP_BUILD="$BUILD_DIR/app"
echo "Configuring universal macOS app..."
cmake -S "$ROOT" -B "$APP_BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$(xcrun --find clang)" \
    -DCMAKE_CXX_COMPILER="$(xcrun --find clang++)" \
    -DCMAKE_AR="$PATCHES_AR" \
    -DCMAKE_PREFIX_PATH="$MACPORTS_PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES='arm64;x86_64' \
    -DPATCHES_C_COMPILER="$PATCHES_CC" \
    -DPATCHES_LD="$PATCHES_LD"
cmake --build "$APP_BUILD" --target Zelda64Recompiled --parallel "$(sysctl -n hw.ncpu)"

APP="$APP_BUILD/Zelda64Recompiled.app"
if [[ ! -d "$APP" ]]; then
    echo "Build completed without producing the expected app bundle: $APP" >&2
    exit 1
fi

PACKAGE_DIR="$BUILD_DIR/package"
ZIP="$PACKAGE_DIR/Zelda64Recompiled-macOS-universal.zip"
DMG="$PACKAGE_DIR/Zelda64Recompiled-macOS-universal.dmg"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

DMG_STAGE="$(mktemp -d "$PACKAGE_DIR/dmg-stage.XXXXXX")"
ditto "$APP" "$DMG_STAGE/Zelda64Recompiled.app"
hdiutil create -volname "Majora's Mask" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG"
rm -rf "$DMG_STAGE"

echo "Build and packaging complete."
echo "App: $APP"
echo "ZIP: $ZIP"
echo "DMG: $DMG"
