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
- **Solo barra de menú, consumo mínimo.** Sin icono en el Dock, sin ventanas hasta que las necesitas, y las dependencias (`mpv`, `yt-dlp`, Homebrew) se detectan e instalan por ti.
- **Teclas multimedia y Centro de Control funcionan de fábrica.** Salta al elemento siguiente/anterior de la playlist sin cambiar de ventana.
- **No se limita a YouTube.** Funciona con cualquier web soportada por `yt-dlp` (cientos de sitios).

## Requisitos

- macOS 13 o superior
- [Swift toolchain](https://www.swift.org) (viene con Xcode / Command Line Tools) para compilar
- [Homebrew](https://brew.sh), [`mpv`](https://mpv.io) y [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) — la propia app los detecta y ofrece instalarlos si faltan

## Compilar

```sh
./build.sh
```

Esto genera `MpvYoutubePlayer.app` en la raíz del proyecto, firmada ad-hoc.

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

Si `mpv` o `yt-dlp` no están instalados, el popover muestra un aviso con un
botón para instalarlos con Homebrew. Si Homebrew tampoco está instalado, se
abre Terminal.app con el instalador oficial precargado — no se ejecuta el
instalador de Homebrew de forma automática porque requiere tu contraseña de
administrador de forma interactiva.

## Estructura del proyecto

- `Sources/MpvYoutubePlayer/DependencyChecker.swift` — detecta `brew`, `mpv` y `yt-dlp`
- `Sources/MpvYoutubePlayer/HomebrewInstaller.swift` — instala paquetes con `brew install` / abre Terminal para instalar Homebrew
- `Sources/MpvYoutubePlayer/MPVLauncher.swift` — mapea calidad → formato de `yt-dlp` y lanza `mpv`
- `Sources/MpvYoutubePlayer/PlayerView.swift` / `PlayerViewModel.swift` — UI del popover
- `Sources/MpvYoutubePlayer/AppDelegate.swift` / `main.swift` — icono de barra de menú y arranque de la app
- `Resources/Info.plist` — metadatos del bundle (`LSUIElement` para que sea solo de barra de menú)
- `build.sh` — compila y empaqueta `MpvYoutubePlayer.app`

## Registro de reproducción

Los logs de `mpv` se guardan en `~/Library/Logs/MpvYoutubePlayer/mpv.log`,
útil si un vídeo no arranca.
