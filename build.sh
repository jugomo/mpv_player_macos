#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MpvYoutubePlayer"
BUNDLE="${APP_NAME}.app"

echo "==> Compilando en modo release…"
swift build -c release

BIN_PATH=".build/release/${APP_NAME}"
if [ ! -f "$BIN_PATH" ]; then
    echo "Error: no se encontró el binario compilado en $BIN_PATH" >&2
    exit 1
fi

echo "==> Generando icono desde icono.png…"
ICON_SRC="icono.png"
ICONSET_DIR=".build/AppIcon.iconset"
ICNS_PATH=".build/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    sips -z 16 16     "$ICON_SRC" --out "${ICONSET_DIR}/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "${ICONSET_DIR}/icon_16x16@2x.png"  >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "${ICONSET_DIR}/icon_32x32.png"     >/dev/null
    sips -z 64 64     "$ICON_SRC" --out "${ICONSET_DIR}/icon_32x32@2x.png"  >/dev/null
    sips -z 128 128   "$ICON_SRC" --out "${ICONSET_DIR}/icon_128x128.png"   >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "${ICONSET_DIR}/icon_256x256.png"   >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "${ICONSET_DIR}/icon_512x512.png"   >/dev/null
    sips -z 1024 1024 "$ICON_SRC" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
    rm -rf "$ICONSET_DIR"
else
    echo "Aviso: no se encontró ${ICON_SRC}, se empaquetará sin icono personalizado." >&2
fi

echo "==> Empaquetando ${BUNDLE}…"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp "$BIN_PATH" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${BUNDLE}/Contents/Info.plist"
if [ -f "$ICNS_PATH" ]; then
    cp "$ICNS_PATH" "${BUNDLE}/Contents/Resources/AppIcon.icns"
fi

echo "==> Firmando ad-hoc…"
codesign --force --deep --sign - "$BUNDLE"

echo "==> Listo: $(pwd)/${BUNDLE}"
echo
echo "Para instalarla:"
echo "  mv \"${BUNDLE}\" /Applications/"
echo "  open \"/Applications/${BUNDLE}\""
echo
echo "O para probarla sin instalarla:"
echo "  open \"${BUNDLE}\""
