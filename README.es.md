<p align="center">
  <img src="icono.png" alt="Icono de mpv YouTube Player" width="128">
</p>

# mpv YouTube Player

*Read this in other languages: [English](README.md)*

App de barra de menú para macOS que reproduce vídeos de YouTube (u otras
webs soportadas por `yt-dlp`) usando `mpv`.

## Por qué usarla

- **Reproduce solo el vídeo, sin tener el navegador abierto.** Sin Chrome/Safari corriendo de fondo, sin recomendaciones automáticas ni anuncios — solo `mpv` reproduciendo el vídeo.
- **Modo solo audio para vídeos musicales.** Descarta la pista de vídeo por completo, ideal para escuchar de fondo con poco consumo.
- **Genera la playlist automáticamente.** Cada vídeo que reproduces se añade a la playlist, con el título obtenido en segundo plano — no hace falta curarla a mano.
- **Sin Homebrew ni dependencias que instalar.** `mpv` y `yt-dlp` van empaquetados dentro de la propia app — la descargas y funciona.
- **Solo barra de menú, consumo mínimo.** Sin icono en el Dock, sin ventanas hasta que las necesitas.
- **Teclas multimedia y Centro de Control funcionan de fábrica.** Salta al elemento siguiente/anterior de la playlist sin cambiar de ventana.
- **No se limita a YouTube.** Funciona con cualquier web soportada por `yt-dlp` (cientos de sitios).

## Requisitos

Para usar la app: solo macOS 13 o superior — `mpv` y `yt-dlp` van
empaquetados dentro de `MpvYoutubePlayer.app`, no hace falta Homebrew.

Para compilarla desde el código fuente, además necesitas:

- [Swift toolchain](https://www.swift.org) (viene con Xcode / Command Line Tools)
- [Homebrew](https://brew.sh) con [`mpv`](https://mpv.io) instalado (`brew install mpv`) — `build.sh` vendoriza esa copia local y sus librerías dentro del bundle, así la app *ya compilada* no necesita Homebrew para nada
- Conexión a internet la primera vez que compiles, para descargar el binario standalone de `yt-dlp` (se cachea después en `.build/vendor/`)

Si en tiempo de ejecución faltan `mpv`/`yt-dlp` (p. ej. ejecutando sin
empaquetar durante el desarrollo), la app recurre a detectar una
instalación de Homebrew y ofrece instalarlos.

## Compilar

```sh
./build.sh
```

Esto genera `MpvYoutubePlayer.app` en la raíz del proyecto, firmada ad-hoc,
con `mpv` (y sus ~47 librerías dinámicas) y `yt-dlp` empaquetados dentro de
`Contents/Resources/{bin,lib}` — ver `scripts/vendor_mpv.py`. El resultado
es una app autocontenida (~100 MB) que funciona en un Mac sin Homebrew.

## Instalar / ejecutar

```sh
mv MpvYoutubePlayer.app /Applications/
open /Applications/MpvYoutubePlayer.app
```

O simplemente `open MpvYoutubePlayer.app` para probarla sin moverla.

Aparecerá un icono ▶️ en la barra de menú (no hay icono en el Dock, es una
app de solo barra de menú). Para que arranque sola al iniciar sesión,
añádela en **Ajustes del Sistema → General → Elementos de inicio**.

## Uso

1. Haz clic en el icono de la barra de menú.
2. Pega la URL del vídeo de YouTube (si ya la tienes copiada, se autocompleta).
3. Elige la calidad deseada.
4. Pulsa **Reproducir**. `mpv` se abre en una ventana aparte con el vídeo.

`mpv` y `yt-dlp` van empaquetados, así que normalmente esto no hace falta.
Si ejecutas la app sin empaquetar durante el desarrollo y de verdad faltan,
el popover muestra un aviso con un botón para instalarlos con Homebrew. Si
Homebrew tampoco está instalado, se abre Terminal.app con el instalador
oficial precargado — no se ejecuta el instalador de Homebrew de forma
automática porque requiere tu contraseña de administrador de forma
interactiva.

## Estructura del proyecto

- `Sources/MpvYoutubePlayer/DependencyChecker.swift` — resuelve el `mpv`/`yt-dlp` empaquetados dentro de la app, y si no están recurre a detectar `brew`, `mpv` y `yt-dlp` en el sistema
- `Sources/MpvYoutubePlayer/HomebrewInstaller.swift` — instala paquetes con `brew install` / abre Terminal para instalar Homebrew (solo como respaldo)
- `scripts/vendor_mpv.py` — copia `mpv` y el cierre de sus dylibs desde Homebrew al bundle de la app y reescribe sus rutas enlazadas a `@rpath`, invocado desde `build.sh`
- `Sources/MpvYoutubePlayer/MPVLauncher.swift` — mapea calidad → formato de `yt-dlp` y lanza `mpv`
- `Sources/MpvYoutubePlayer/PlayerView.swift` / `PlayerViewModel.swift` — UI del popover
- `Sources/MpvYoutubePlayer/AppDelegate.swift` / `main.swift` — icono de barra de menú y arranque de la app
- `Resources/Info.plist` — metadatos del bundle (`LSUIElement` para que sea solo de barra de menú)
- `build.sh` — compila y empaqueta `MpvYoutubePlayer.app`

## Registro de reproducción

Los logs de `mpv` se guardan en `~/Library/Logs/MpvYoutubePlayer/mpv.log`,
útil si un vídeo no arranca.
