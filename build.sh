#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MpvPlayerUI"
BUNDLE="${APP_NAME}.app"

# Identidad de firma para todo el bundle (la app y cada binario vendorizado
# dentro: mpv y sus dylibs, yt-dlp, deno, el proveedor de PO Token…). Por
# defecto ad-hoc ("-"), como siempre. Problema conocido de firmar ad-hoc: al
# no tener una identidad estable (sin certificado, cada firma es distinta),
# macOS trata cada reconstrucción como "una app distinta" en su base de
# permisos (Ajustes > Privacidad y seguridad > Archivos y carpetas): hay que
# volver a conceder acceso a archivos locales cada vez que se reconstruye,
# aunque ya se hubiera concedido antes.
#
# Con un certificado de firma de código estable —uno autofirmado creado una
# sola vez en Acceso a Llaveros ("Asistente de certificados > Crear un
# certificado…", tipo "Firma de código"), o uno de pago de Apple Developer
# Program— los permisos concedidos sobreviven a futuras reconstrucciones,
# porque la identidad ya no cambia entre ellas:
#   CODESIGN_IDENTITY="Mi Certificado" ./build.sh
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

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
        -exec codesign --force --sign "$CODESIGN_IDENTITY" {} \;
elif [ -n "$MPV_SOURCE" ]; then
    python3 scripts/vendor_mpv.py "$MPV_SOURCE" "${BUNDLE}/Contents/Resources" "$CODESIGN_IDENTITY"
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
    YTDLP_CACHE_VERSION="${YTDLP_CACHE}.version"
    # A diferencia de mpv/deno/bgutil (versionados a propósito, ver más
    # abajo), yt-dlp SÍ debe ser siempre el más reciente posible en cada
    # build: YouTube le cambia las reglas casi cada semana (ver historial de
    # MPVLauncher.applySessionSettings — un yt-dlp de 6 semanas fue
    # literalmente la causa de que la reproducción se cortara siempre a los
    # pocos segundos). Antes esto se cacheaba sin fecha de caducidad y solo
    # se refrescaba borrándolo a mano; ahora se compara contra la última
    # release publicada en cada build y se vuelve a descargar si difiere.
    # --retry: esta comprobación (y la descarga de abajo) se ha visto fallar
    # por cortes de red intermitentes de pocos segundos, no por que la API/el
    # release realmente no estén disponibles — reintentar en vez de rendirse
    # al primer timeout evita tener que relanzar el build entero a mano.
    LATEST_YTDLP_TAG="$(curl -fsSL -m 10 --retry 5 --retry-delay 3 --retry-all-errors \
        https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null || true)"
    CACHED_YTDLP_TAG=""
    [ -f "$YTDLP_CACHE_VERSION" ] && CACHED_YTDLP_TAG="$(cat "$YTDLP_CACHE_VERSION")"

    if [ -n "$LATEST_YTDLP_TAG" ] && [ "$LATEST_YTDLP_TAG" != "$CACHED_YTDLP_TAG" ]; then
        echo "    Descargando yt-dlp ${LATEST_YTDLP_TAG} (caché tenía: ${CACHED_YTDLP_TAG:-ninguna})…"
        mkdir -p "$(dirname "$YTDLP_CACHE")"
        # -C - reanuda desde donde se cortó en vez de volver a empezar de
        # cero en cada reintento (--retry por sí solo no lo hace).
        curl -fL --progress-bar --connect-timeout 15 --retry 5 --retry-delay 3 \
            --retry-all-errors -C - -o "$YTDLP_CACHE" \
            "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
        chmod +x "$YTDLP_CACHE"
        xattr -d com.apple.quarantine "$YTDLP_CACHE" 2>/dev/null || true
        echo "$LATEST_YTDLP_TAG" > "$YTDLP_CACHE_VERSION"
    elif [ -x "$YTDLP_CACHE" ]; then
        echo "    (usando copia en caché ${CACHED_YTDLP_TAG:-(versión desconocida)}$( [ -z "$LATEST_YTDLP_TAG" ] && echo "; no se pudo consultar la última release, ¿sin red?" ))"
    else
        echo "Error: no hay copia en caché de yt-dlp y no se pudo consultar/descargar la última release (¿sin red?)." >&2
        exit 1
    fi
    cp "$YTDLP_CACHE" "${BUNDLE}/Contents/Resources/bin/yt-dlp"
fi

# YouTube exige cada vez más un "PO Token" antes de servir el vídeo/audio, o
# responde 403 incluso con una URL recién extraída (ver POTProviderLauncher).
# bgutil-ytdlp-pot-provider genera ese token: un plugin de yt-dlp que habla
# por HTTP con un servidor local, ejecutado aquí con un runtime Deno
# vendorizado (evita depender de Node/Homebrew en la máquina final). No hay
# binario precompilado del servidor, así que se compila/instala una vez en
# esta máquina y se cachea en .build/vendor/ (bórralo para forzar una
# actualización); su ausencia no es fatal, solo se pierde esta mitigación de
# los 403 (ver DependencyChecker/POTProviderLauncher, que lo tratan como
# opcional).
BGUTIL_VERSION="1.3.1"

case "$(uname -m)" in
    arm64)   DENO_ASSET="deno-aarch64-apple-darwin.zip" ;;
    x86_64)  DENO_ASSET="deno-x86_64-apple-darwin.zip" ;;
    *)       DENO_ASSET="" ;;
esac

if [ ! -x "${BUNDLE}/Contents/Resources/bin/deno" ] && [ -n "$DENO_ASSET" ]; then
    echo "==> Vendorizando Deno (runtime del proveedor de PO Token)…"
    DENO_CACHE=".build/vendor/${DENO_ASSET}"
    if [ ! -f "$DENO_CACHE" ]; then
        mkdir -p "$(dirname "$DENO_CACHE")"
        curl -fL --progress-bar -o "$DENO_CACHE" \
            "https://github.com/denoland/deno/releases/latest/download/${DENO_ASSET}"
    else
        echo "    (usando copia en caché: ${DENO_CACHE}; bórrala para forzar una actualización)"
    fi
    mkdir -p "${BUNDLE}/Contents/Resources/bin"
    unzip -q -o "$DENO_CACHE" -d "${BUNDLE}/Contents/Resources/bin"
    chmod +x "${BUNDLE}/Contents/Resources/bin/deno"
    xattr -d com.apple.quarantine "${BUNDLE}/Contents/Resources/bin/deno" 2>/dev/null || true
fi
DENO_BIN="$(pwd)/${BUNDLE}/Contents/Resources/bin/deno"

BGUTIL_SRC_CACHE=".build/vendor/bgutil-ytdlp-pot-provider"
if [ ! -d "$BGUTIL_SRC_CACHE" ]; then
    echo "==> Descargando bgutil-ytdlp-pot-provider ${BGUTIL_VERSION}…"
    git clone --quiet --single-branch --branch "$BGUTIL_VERSION" \
        https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git "$BGUTIL_SRC_CACHE"
    # Sin esto `deno install` también instala las devDependencies del
    # proyecto (typescript, eslint, prettier…, ~80MB de más): no hacen falta
    # para nada en tiempo de ejecución, solo para desarrollarlo. Se borra
    # también el lockfile de npm, que si no `deno install` lo prioriza sobre
    # package.json y las reinstala igualmente.
    python3 -c "
import json
path = '${BGUTIL_SRC_CACHE}/server/package.json'
with open(path) as f:
    pkg = json.load(f)
pkg.pop('devDependencies', None)
pkg.pop('scripts', None)
with open(path, 'w') as f:
    json.dump(pkg, f, indent=2)
"
    rm -f "${BGUTIL_SRC_CACHE}/server/deno.lock" "${BGUTIL_SRC_CACHE}/server/package-lock.json"
fi
if [ ! -d "${BGUTIL_SRC_CACHE}/server/node_modules" ] && [ -x "$DENO_BIN" ]; then
    echo "==> Instalando dependencias del proveedor de PO Token (deno install, puede tardar)…"
    ( cd "${BGUTIL_SRC_CACHE}/server" && "$DENO_BIN" install --allow-scripts=npm:canvas )
fi
if [ -d "${BGUTIL_SRC_CACHE}/server/node_modules" ]; then
    rm -rf "${BUNDLE}/Contents/Resources/bgutil-provider"
    mkdir -p "${BUNDLE}/Contents/Resources/bgutil-provider"
    cp -R "${BGUTIL_SRC_CACHE}/server/src" "${BUNDLE}/Contents/Resources/bgutil-provider/"
    cp -R "${BGUTIL_SRC_CACHE}/server/node_modules" "${BUNDLE}/Contents/Resources/bgutil-provider/"
    # Deno resuelve los imports npm (p.ej. "express") contra el package.json
    # más cercano subiendo desde el script de entrada, no solo contra
    # node_modules/: sin esto falla con "Import 'express' not a dependency".
    cp "${BGUTIL_SRC_CACHE}/server/package.json" "${BUNDLE}/Contents/Resources/bgutil-provider/"
fi

BGUTIL_PLUGIN_CACHE=".build/vendor/bgutil-ytdlp-pot-provider-plugin.zip"
if [ ! -f "$BGUTIL_PLUGIN_CACHE" ]; then
    echo "==> Descargando el plugin de yt-dlp para bgutil-ytdlp-pot-provider…"
    mkdir -p "$(dirname "$BGUTIL_PLUGIN_CACHE")"
    curl -fL --progress-bar -o "$BGUTIL_PLUGIN_CACHE" \
        "https://github.com/Brainicism/bgutil-ytdlp-pot-provider/releases/latest/download/bgutil-ytdlp-pot-provider.zip"
fi
# yt-dlp busca plugins en <ruta-del-ejecutable>/yt-dlp-plugins/<nombre-paquete>/yt_dlp_plugins/…
PLUGIN_DEST="${BUNDLE}/Contents/Resources/bin/yt-dlp-plugins/bgutil-ytdlp-pot-provider"
rm -rf "$PLUGIN_DEST"
mkdir -p "$PLUGIN_DEST"
unzip -q -o "$BGUTIL_PLUGIN_CACHE" -d "$PLUGIN_DEST"

if [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "==> Firmando ad-hoc…"
else
    echo "==> Firmando con '${CODESIGN_IDENTITY}'…"
fi
codesign --force --sign "$CODESIGN_IDENTITY" "${BUNDLE}/Contents/Resources/bin/yt-dlp"
if [ -x "${BUNDLE}/Contents/Resources/bin/deno" ]; then
    codesign --force --sign "$CODESIGN_IDENTITY" "${BUNDLE}/Contents/Resources/bin/deno"
fi
if [ -d "${BUNDLE}/Contents/Resources/bgutil-provider" ]; then
    find "${BUNDLE}/Contents/Resources/bgutil-provider" -type f \( -name "*.node" -o -name "*.dylib" \) \
        -exec codesign --force --sign "$CODESIGN_IDENTITY" {} \;
fi
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$BUNDLE"

echo "==> Listo: $(pwd)/${BUNDLE}"
echo
echo "Para instalarla:"
echo "  mv \"${BUNDLE}\" /Applications/"
echo "  open \"/Applications/${BUNDLE}\""
echo
echo "O para probarla sin instalarla:"
echo "  open \"${BUNDLE}\""
