<p align="center">
  <img src="icono.png" alt="Icono de mpv player UI" width="128">
</p>

# mpv player UI

*Read this in other languages: [English](README.md)*

App de barra de menú para macOS que reproduce vídeos de YouTube (u otras
webs soportadas por `yt-dlp`) usando `mpv`.

<p align="center">
  <img src="promo/promo-audio.png" alt="Modo solo audio, mostrando la carátula del vídeo junto al vúmetro digital" width="70%">
</p>

## Propiedad y colaboraciones

Este proyecto ha sido creado por [@jugomo](https://github.com/jugomo) y
está licenciado bajo la [Licencia MIT](LICENSE). Cualquier persona es
bienvenida a usar este software bajo su propia responsabilidad, a
copiarlo o crear un fork citando al autor original, y a colaborar en su
desarrollo, ya sea abriendo un pull request o sugiriendo mejoras a
través de un issue. No se ofrece ninguna garantía.

Nota: la licencia MIT aplica solo al código fuente propio de este
proyecto. La app hace uso de `mpv` (licencia GPL) y `yt-dlp` (dominio
público / Unlicense) una vez instalados en tu máquina; ambos conservan
sus propias licencias originales.

## Aviso

Este proyecto es un experimento personal y educativo, sin ánimo de lucro
ni afiliación con YouTube, Google o sus marcas. Reproduce contenido en
streaming usando `mpv` y `yt-dlp` bajo tu propia responsabilidad; no
descarga ni redistribuye vídeos, ni elude restricciones de edad/región
o medidas de protección de contenido. De este proyecto no se distribuyen
binarios ni compilados, solo el código fuente.

## Por qué usarla

- **Reproduce solo el vídeo, sin tener el navegador abierto.** Sin Chrome/Safari corriendo de fondo ni recomendaciones automáticas — solo `mpv` reproduciendo el vídeo.
- **Modo solo audio a tu manera.** Descarta la pista de vídeo para escuchar de fondo con poco consumo, y elige en Ajustes si `mpv` abre su propia ventana (minimizada automáticamente) o ninguna — la reproducción sigue siendo controlable al 100% desde la app en ambos casos.
- **Reproduce también archivos locales.** Abre uno o varios archivos multimedia de tu ordenador directamente desde el popover — el primero se reproduce de inmediato y el resto se encolan en la playlist en el mismo orden en que los elegiste. Los archivos de audio local pasan automáticamente a modo solo audio (con carátula local, si hay una imagen con el mismo nombre junto al archivo) sin importar la calidad guardada.
- **Playlist que se gestiona sola.** Cada vídeo que reproduces se añade, con el título obtenido en segundo plano — no hace falta curarla a mano. Encadena automáticamente con el siguiente ítem al terminar uno, las filas se reordenan arrastrándolas y toda la playlist se importa/exporta como archivo `.pl`.
- **Usa el `mpv`/`yt-dlp` que ya tienes instalados.** La app no añade ninguna herramienta nueva a tu sistema, simplemente los invoca.
- **Solo barra de menú, consumo mínimo.** Sin icono en el Dock, sin ventanas hasta que las necesitas.
- **Teclas multimedia y Centro de Control funcionan de fábrica.** Salta al elemento siguiente/anterior de la playlist sin cambiar de ventana.
- **No se limita a YouTube.** Funciona con cualquier web soportada por `yt-dlp` (cientos de sitios).
- **Controles de reproducción completos en el propio popover.** Anterior/reproducir-pausar/detener/siguiente, una barra de progreso con el tiempo transcurrido/restante, un botón de pantalla completa y otro de fijar siempre encima (ambos cuando hay vídeo), y un slider de volumen independiente del volumen del sistema de macOS — sin tener que abrir la ventana de `mpv`.
- **Vúmetro y carátula al reproducir solo audio.** Un medidor de nivel estéreo junto a los controles, con agujas analógicas de verdad o tiras LED digitales — haz clic para cambiar de estilo — que reacciona al nivel real del audio y al volumen propio de la app, junto con la miniatura propia del vídeo para que la pantalla no sean solo medidores y texto.
- **El icono de la barra de menú refleja lo que pasa.** Gira mientras un vídeo se está inicializando y parpadea entre reproducir/pausa mientras está pausado, para saber el estado de un vistazo sin abrir el popover.
- **La playlist destaca el vídeo que se está reproduciendo**, en una ventana que puedes redimensionar, acoplar bajo el popover o desacoplar flotante — tanto el tamaño como el estado acoplado/flotante se recuerdan entre reinicios.
- **Caché de vídeo y calidad de renderizado configurables**, para ajustar la latencia de arranque frente a la estabilidad de reproducción, y el uso de GPU/batería frente a la nitidez en pantalla completa.
- **Interfaz en español/inglés**, cambiable desde Ajustes sin reiniciar la app.
- **Vigila sus propias herramientas vendorizadas.** El panel Acerca de avisa discretamente cuando hay una versión más reciente de `mpv`/`yt-dlp` disponible aguas arriba, ya que ambas van empaquetadas dentro de la app en vez de gestionarse con un gestor de paquetes en tiempo de ejecución.

## Requisitos

Para usar la app: macOS 13 o superior, y tener [`mpv`](https://mpv.io) y
[`yt-dlp`](https://github.com/yt-dlp/yt-dlp) instalados en tu sistema
(por ejemplo con Homebrew: `brew install mpv yt-dlp`). La app los detecta
automáticamente una vez instalados.

Para compilarla desde el código fuente, además necesitas:

- [Swift toolchain](https://www.swift.org) (viene con Xcode / Command Line Tools)
- [Homebrew](https://brew.sh) con [`mpv`](https://mpv.io) instalado (`brew install mpv`), usado como referencia local durante la compilación
  - Si tu versión de macOS o arquitectura ya no tiene bottle precompilado en Homebrew (p. ej. Ventura en Intel), alternativas: instalar mpv con [MacPorts](https://www.macports.org) (`sudo port install mpv`, se detecta solo), forzar a Homebrew a compilar desde fuente (`brew install mpv --build-from-source`, requiere Xcode Command Line Tools), o pasarle a `build.sh` la ruta de cualquier binario de `mpv` con `MPV_BIN=/ruta/a/mpv ./build.sh`
- Conexión a internet la primera vez que compiles, para descargar el binario standalone de `yt-dlp` (se cachea después en `.build/vendor/`)

Si en tiempo de ejecución faltan `mpv`/`yt-dlp` en tu sistema, la app
recurre a detectar una instalación de Homebrew y ofrece instalarlos.

## Compilar

```sh
./build.sh
```

Esto genera `MpvPlayerUI.app` en la raíz del proyecto, usando como
referencia el `mpv` (y sus ~47 librerías dinámicas) y el `yt-dlp`
disponibles localmente — ver `scripts/vendor_mpv.py`.

Por defecto todo se firma ad-hoc (`CODESIGN_IDENTITY="-"`), como
siempre. Si tienes un certificado de firma de código estable (uno
autofirmado creado una vez en Acceso a Llaveros, o uno de pago de Apple
Developer Program), pásalo para que los permisos de acceso a
archivos/Finder que macOS concede a la app no haya que volver a
concederlos tras cada reconstrucción — con firma ad-hoc, cada
reconstrucción le parece a macOS "una app distinta" porque la firma
cambia cada vez:

```sh
CODESIGN_IDENTITY="Mi Certificado" ./build.sh
```

## Instalar / ejecutar

```sh
mv MpvPlayerUI.app /Applications/
open /Applications/MpvPlayerUI.app
```

O simplemente `open MpvPlayerUI.app` para probarla sin moverla.

Aparecerá un icono ▶️ en la barra de menú (no hay icono en el Dock, es una
app de solo barra de menú). Para que arranque sola al iniciar sesión,
añádela en **Ajustes del Sistema → General → Elementos de inicio**.

## Uso

1. Haz clic en el icono de la barra de menú.
2. Pulsa el icono de enlace junto al título (arranca colapsado) para
   desplegar el formulario y pega ahí la URL del vídeo (si ya
   la tienes copiada, se autocompleta), o pulsa el icono de carpeta para
   elegir uno o varios archivos locales en su lugar.
3. Elige la calidad deseada (no aplica a archivos locales — se
   reproducen tal cual).
4. Pulsa **Reproducir**. `mpv` se abre en una ventana aparte con el vídeo.

Mientras el vídeo carga, el icono de la barra de menú gira; vuelve a la
normalidad en cuanto `mpv` empieza realmente a mostrarlo. Con algo ya en
reproducción, usa los botones de anterior/reproducir-pausar/detener/
siguiente del popover (o las teclas multimedia / Centro de Control) para
controlarlo, arrastra la barra de progreso para saltar a una posición, y
usa el slider de volumen para ajustar solo la reproducción de esta app —
nunca toca el volumen del sistema de macOS. Con el popover activo, las
flechas ← → saltan 5 segundos atrás/adelante y las flechas ↑ ↓ ajustan
el volumen. Si hay vídeo, aparecen un
botón de pantalla completa y otro de fijar siempre encima (un pin) junto
al de playlist — el estado del pin se recuerda entre vídeos y entre
reinicios de la app, así que la ventana de `mpv` arranca ya fijada encima
del resto si la dejaste activada; en modo solo audio aparecen en
su lugar un vúmetro y la carátula del vídeo junto al título (haz clic en
el vúmetro para alternar entre el estilo digital y el analógico). El
botón de reproducir se convierte en pausa automáticamente, y el icono de
la barra de menú parpadea entre reproducir/pausa mientras está en pausa.
Al terminar un ítem, la reproducción encadena automáticamente con el
siguiente de la playlist.

Abre **Playlist** para ver, reproducir de nuevo, reordenar o exportar
vídeos anteriores; el que se está reproduciendo aparece destacado.
Arrastra una fila por su icono de asa para reordenarla, o deslízala hacia
la izquierda para revelar las acciones de eliminar/copiar URL. Usa
**Importar…**/**Exportar…** arriba para mover toda la playlist entre
equipos como archivo `.pl`. La propia ventana de playlist se puede
redimensionar arrastrando su borde superior/inferior, y alternar entre
acoplada (bajo el popover) y flotante con el botón junto a su título —
tanto el tamaño como el estado acoplado/flotante se recuerdan entre
reinicios.

Si `mpv`/`yt-dlp` no están instalados en tu sistema, el popover muestra un
aviso con un botón para instalarlos con Homebrew. Si Homebrew tampoco está
instalado, se abre Terminal.app con el instalador oficial precargado — no
se ejecuta el instalador de Homebrew de forma automática porque requiere
tu contraseña de administrador de forma interactiva.

## Ajustes

Clic derecho en el icono de la barra de menú para abrir **Ajustes** (la
Ayuda también vive ahora en ese mismo menú de clic derecho). Tiene dos
pestañas:

**General:**

- **Idioma** — español/inglés, se aplica al momento sin reiniciar.
- **Caché de vídeo** — "Arranque rápido" (5s de adelanto), "Reproducción estable" (30s), o una duración personalizada con el slider; controla `--demuxer-readahead-secs` de `mpv`.
- **Renderizado de vídeo** — "Rendimiento" fuerza un escalador bilineal barato (menor uso de GPU/batería en pantalla completa) o "Calidad" deja el escalador más nítido por defecto de `mpv`.
- **Ventana en modo solo audio** — activa si `mpv` abre su propia ventana (minimizada automáticamente) al reproducir solo audio, o ninguna; en ambos casos la reproducción sigue siendo controlable al 100% desde los botones, la barra de progreso y el vúmetro de la propia app.
- **Cerrar ventanas al reproducir** — activado por defecto: el popover principal y la ventana de playlist se cierran solos al empezar a reproducir. Desactívalo para que el popover principal quede visible aunque pierda el foco (p. ej. mientras interactúas con la ventana propia de `mpv`) — para cerrarlo, vuelve a hacer clic en el icono de la barra de menú.

**Registro** — muestra la cola del log de `mpv` directamente en la app,
con botones para recargarlo, exportarlo a un `.txt` o vaciarlo. Ver
[Registro de reproducción](#registro-de-reproducción) más abajo para
saber dónde vive el archivo.

La ventana **Acerca de** (también en el menú de clic derecho) muestra
además un aviso cuando hay una versión más reciente de `mpv` o `yt-dlp`
disponible aguas arriba — como ambos van vendorizados en el bundle de
la app, aplicarla significa recompilar con `build.sh`, no una
actualización desde dentro de la app.

## Estructura del proyecto

- `Sources/MpvPlayerUI/DependencyChecker.swift` — detecta `brew`, `mpv` y `yt-dlp` instalados en el sistema
- `Sources/MpvPlayerUI/HomebrewInstaller.swift` — instala paquetes con `brew install` / abre Terminal para instalar Homebrew
- `scripts/vendor_mpv.py` — copia `mpv` y el cierre de sus dylibs desde una instalación local al bundle de la app y reescribe sus rutas enlazadas a `@rpath`, invocado desde `build.sh`
- `Sources/MpvPlayerUI/MPVLauncher.swift` — mapea calidad → formato de `yt-dlp` y lanza `mpv`; se comunica con él por su socket JSON IPC (`MPVIPCClient.swift`) para observar el estado de pausa/título/posición y detectar el momento en que la reproducción realmente empieza
- `Sources/MpvPlayerUI/UpdateChecker.swift` — chequeo en segundo plano, una vez al día y cacheado, de las versiones de `mpv`/`yt-dlp` empaquetadas frente a su última versión aguas arriba, mostrado en `AboutView`
- `Sources/MpvPlayerUI/PlayerView.swift` / `PlayerViewModel.swift` — UI del popover y estado de reproducción (carga, pausa, elemento actual, posición de la barra de progreso, volumen, niveles del vúmetro), incluida la apertura de archivos locales y el avance automático al siguiente ítem de la playlist
- `Sources/MpvPlayerUI/VUMeterView.swift` / `VUMeterSettings.swift` — el vúmetro estéreo digital/analógico que se muestra en modo solo audio, y su preferencia de estilo persistida; los niveles vienen del filtro de audio `astats` de `mpv`, leído por IPC
- `Sources/MpvPlayerUI/CacheSettings.swift` / `RenderSettings.swift` / `PlaybackWindowSettings.swift` — estado persistido de Ajustes (caché de vídeo, calidad de renderizado, comportamiento de la ventana en solo audio, si el popover/la ventana de playlist se cierran al reproducir, y el estado acoplado/flotante y tamaño de la ventana de playlist), compartido entre `SettingsView` y `MPVLauncher`/`AppDelegate`
- `Sources/MpvPlayerUI/PlaylistItem.swift` / `PlaylistStore.swift` — modelo del ítem de playlist (archivo local vs. URL, calidad, título/descripción obtenidos) y su persistencia JSON/importación/exportación a un archivo `.pl`
- `Sources/MpvPlayerUI/YtDlpMetadataFetcher.swift` — obtiene la descripción de un vídeo bajo demanda vía `yt-dlp` (el IPC de mpv solo expone el título)
- `Sources/MpvPlayerUI/PlaylistView.swift` — ventana de playlist: destaca el elemento que se está reproduciendo, arrastrar para reordenar, acciones por swipe, alternar acoplada/flotante
- `Sources/MpvPlayerUI/SettingsView.swift` — pestaña General (idioma, caché, renderizado, ventana en solo audio) y pestaña Registro
- `Sources/MpvPlayerUI/LogViewerView.swift` — visor del log de `mpv` dentro de la app, con recargar/exportar/vaciar
- `Sources/MpvPlayerUI/AboutView.swift` — ventana de Ayuda/Acerca de, incluido el aviso de actualización de herramientas vendorizadas
- `Sources/MpvPlayerUI/TitleToastView.swift` — el aviso "reproduciendo ahora" que aparece fuera de la ventana de `mpv`
- `Sources/MpvPlayerUI/Localization.swift` — tabla de textos ES/EN propia, cambiable en caliente desde Ajustes
- `Sources/MpvPlayerUI/AppDelegate.swift` / `App.swift` — icono de barra de menú (incluidas las animaciones de carga/pausa) y arranque de la app
- `Resources/Info.plist` — metadatos del bundle (`LSUIElement` para que sea solo de barra de menú)
- `build.sh` — compila y empaqueta `MpvPlayerUI.app`

## Registro de reproducción

Los logs de `mpv` se guardan en `~/Library/Logs/MpvPlayerUI/mpv.log`,
útil si un vídeo no arranca — o ábrelo directamente desde Ajustes →
Registro, que también puede exportarlo o vaciarlo.
