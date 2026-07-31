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

case "$(uname -m)" in
    arm64)   DEPS_ZIP="mpv-deps-macos-applesilicon.zip" ;;
    x86_64)  DEPS_ZIP="mpv-deps-macos-intel.zip" ;;
    *)       DEPS_ZIP="" ;;
esac

echo "==> Vendorizando mpv y sus dependencias (para no requerir Homebrew en la máquina final)…"
MPV_SOURCE="${MPV_BIN:-}"
if [ -n "$MPV_SOURCE" ] && [ ! -x "$MPV_SOURCE" ]; then
    echo "Error: MPV_BIN='${MPV_SOURCE}' no existe o no es ejecutable." >&2
    exit 1
fi
if [ -z "$MPV_SOURCE" ]; then
    for dir in /opt/homebrew/bin /usr/local/bin /opt/local/bin; do
        if [ -x "${dir}/mpv" ]; then
            MPV_SOURCE="${dir}/mpv"
            break
        fi
    done
fi

FROM_ZIP=0
if [ -z "$MPV_SOURCE" ] && [ -n "$DEPS_ZIP" ] && [ -f "$DEPS_ZIP" ]; then
    echo "No se encontró mpv instalado, pero hay dependencias vendorizadas para tu arquitectura ($(uname -m)) en '${DEPS_ZIP}'."
    ans="s"
    if [ -t 0 ]; then
        read -r -p "¿Instalar mpv/yt-dlp desde ese zip en vez de requerir Homebrew/MacPorts? [S/n] " ans
    else
        echo "    (entorno no interactivo: se usa el zip automáticamente)"
    fi
    case "$ans" in
        [nN]*) ;;
        *) FROM_ZIP=1 ;;
    esac
fi

if [ "$FROM_ZIP" -eq 1 ]; then
    echo "==> Instalando mpv y yt-dlp desde ${DEPS_ZIP}…"
    unzip -q -o "$DEPS_ZIP" -d "${BUNDLE}/Contents/Resources"
    chmod +x "${BUNDLE}/Contents/Resources/bin/"*
    find "${BUNDLE}/Contents/Resources/bin" "${BUNDLE}/Contents/Resources/lib" -type f \
        -exec codesign --force --sign - {} \;
elif [ -n "$MPV_SOURCE" ]; then
    python3 scripts/vendor_mpv.py "$MPV_SOURCE" "${BUNDLE}/Contents/Resources"
else
    echo "Error: no se encontró mpv instalado en esta máquina; hace falta para vendorizarlo en el bundle. Alternativas:" >&2
    echo "  - Homebrew: 'brew install mpv' (si tu macOS/arquitectura no tiene bottle precompilado, prueba 'brew install mpv --build-from-source', requiere Xcode Command Line Tools)" >&2
    echo "  - MacPorts: 'sudo port install mpv' (se detecta automáticamente en /opt/local/bin)" >&2
    echo "  - Un binario de mpv obtenido por otra vía: 'MPV_BIN=/ruta/a/mpv ./build.sh'" >&2
    if [ -n "$DEPS_ZIP" ]; then
        echo "  - Un zip de dependencias vendorizadas '${DEPS_ZIP}' en la raíz del proyecto (no encontrado en esta máquina)" >&2
    fi
    exit 1
fi

if [ ! -x "${BUNDLE}/Contents/Resources/bin/yt-dlp" ]; then
    echo "==> Vendorizando yt-dlp (binario standalone, sin dependencias de Python/Homebrew)…"
    YTDLP_CACHE=".build/vendor/yt-dlp_macos"
    if [ ! -x "$YTDLP_CACHE" ]; then
        mkdir -p "$(dirname "$YTDLP_CACHE")"
        curl -fL --progress-bar -o "$YTDLP_CACHE" \
            "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
        chmod +x "$YTDLP_CACHE"
        xattr -d com.apple.quarantine "$YTDLP_CACHE" 2>/dev/null || true
    else
        echo "    (usando copia en caché: ${YTDLP_CACHE}; bórrala para forzar una actualización)"
    fi
    cp "$YTDLP_CACHE" "${BUNDLE}/Contents/Resources/bin/yt-dlp"
fi

echo "==> Firmando ad-hoc…"
codesign --force --sign - "${BUNDLE}/Contents/Resources/bin/yt-dlp"
codesign --force --deep --sign - "$BUNDLE"

echo "==> Listo: $(pwd)/${BUNDLE}"
echo
echo "Para instalarla:"
echo "  mv \"${BUNDLE}\" /Applications/"
echo "  open \"/Applications/${BUNDLE}\""
echo
echo "O para probarla sin instalarla:"
echo "  open \"${BUNDLE}\""
