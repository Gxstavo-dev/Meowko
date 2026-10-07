<p align="center">
  <img src="assets/gato_icon.png" alt="Gato naranja" width="120">
</p>

# meowko

**Un widget de Wayland para chatear con [opencode](https://opencode.ai), en el panel superior.**

Un gatito que duerme cuando opencode está inactivo, se despierta mientras contesta y te avisa con un parpadeo cuando la respuesta llegó.

---

## Índice

- [Qué hace](#qué-hace)
- [Comandos](#comandos)
- [Cómo funciona por dentro](#cómo-funciona-por-dentro)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Autostart](#autostart)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Referencia de `meowko.qml`](#referencia-de-meowkoqml)
- [Referencia de `Cat.qml`](#referencia-de-catqml)
- [Personalización](#personalización)
- [Problemas conocidos](#problemas-conocidos)
- [Roadmap](#roadmap)
- [Licencia](#licencia)

---

## Qué hace

Un botón flotante anclado al borde superior de la pantalla. Cerrado es una barrita negra de 44×18 px con dos ojitos que parpadean de vez en cuando. Al hacer clic se abre una burbuja negra de 600×340 px con la conversación.

| Acción                                                       | Resultado                                                          |
| ------------------------------------------------------------ | ------------------------------------------------------------------ |
| Escribir algo y pulsar `Enter`                               | Se envía a `opencode run` y aparecen tres puntitos parpadeando     |
| Escribir `/`                                                 | Aparece el autocompletado de [comandos](#comandos); `Tab` completa |
| Llega la respuesta                                           | Aparece el texto y suena un aviso                                  |
| Hay respuesta y el widget está cerrado                       | La barrita parpadea de negro a blanco muy despacio                 |
| Abrir el widget                                              | El foco salta al input y el parpadeo se corta                      |
| `Esc` dos veces, botón ■ o `/cancel` con una petición activa | Cancela la petición (conserva el texto que hubiera llegado)        |
| `Esc` sin petición activa                                    | Cierra el widget                                                   |
| Clic en el modelo del encabezado                             | Lista los modelos disponibles (igual que `/models`)                |
| Clic en el ícono de volumen                                  | Silencia el aviso (no afecta el parpadeo)                          |
| Clic en el ícono de copiar                                   | Copia la respuesta al portapapeles y muestra un ✓ durante 1,2 s    |
| Clic en "nuevo"                                              | Borra la conversación y la sesión guardada                         |

El gato junto al input indica el estado: **dormido** si opencode no hace nada, **tranquilo** si está trabajando.

El encabezado muestra el ID de la sesión y el modelo/agente activos. Modelo, agente y directorio de trabajo se guardan entre reinicios.

### Dos detalles de diseño

**La capa.** Usa `wlr-layer-shell` en `WlrLayer.Overlay` con `exclusionMode: Ignore`: flota sobre todo sin reservar espacio en la barra del compositor. El `mask: Region { item: box }` recorta la superficie invisible para que los clics fuera del widget no se intercepten.

**El parpadeo de alerta.** No alterna entre blanco y negro de golpe: interpola. `flash` sube y baja con `Easing.InOutSine` y el color de fondo se calcula mezclando `cBg` hacia blanco según ese valor. Los ojitos se invierten a negro con la misma variable; si no, desaparecerían sobre el fondo blanco. El ciclo dura 8 s: 2,6 s de fundido, 1,4 s de pausa, 2,6 s de vuelta y 1,4 s de pausa.

---

## Comandos

Los mensajes que empiezan con `/` los resuelve el widget y **no** se envían a opencode.

| Comando                     | Qué hace                                                                     |
| --------------------------- | ---------------------------------------------------------------------------- |
| `/help`                     | Lista los comandos                                                           |
| `/model`                    | Muestra el modelo activo                                                     |
| `/model <proveedor/modelo>` | Cambia el modelo. Acepta un fragmento si solo coincide uno (`/model sonnet`) |
| `/model default`            | Vuelve al modelo por defecto de opencode                                     |
| `/models [filtro]`          | Lista los modelos disponibles (`opencode models`), con filtro opcional       |
| `/agent [nombre]`           | Muestra o cambia el agente (`/agent plan`); `/agent default` lo quita        |
| `/agents`                   | Lista los agentes (`opencode agent list`)                                    |
| `/sessions`                 | Lista las sesiones (`opencode session list`)                                 |
| `/session <id>`             | Continúa una sesión por ID                                                   |
| `/new` o `/clear`           | Nueva conversación                                                           |
| `/cd <ruta>`                | Cambia el directorio de trabajo de opencode (inicia una conversación nueva)  |
| `/cancel`                   | Cancela la petición en curso                                                 |
| `/mute`                     | Silencia o reactiva el aviso sonoro                                          |

El modelo y el agente se pasan a opencode con `--model` y `--agent` en cada petición. Las sesiones pertenecen a un directorio, por eso `/cd` abre una conversación nueva.

---

## Cómo funciona por dentro

No hay servidor, ni TUI, ni terminal oculta. El widget lanza el binario de opencode y lee su salida JSON.

```
┌─ shell.qml (ShellRoot) ──────────────────────────────────┐
│                                                          │
│  Process { id: proc }                                    │
│    └─ sh -c 'exec opencode run --format json ...'        │
│         └─ stdout ─► StdioCollector ─► handleOutput()    │
│              └─ parsea cada línea JSON                   │
│                   ├─ sessionID ─► FileView (a disco)     │
│                   └─ type:"text" ─► ListModel chat       │
│                                                          │
│  Process { id: lister } ─► opencode models / agent list  │
│  Process { id: bell }   ─► pw-play complete.oga          │
│                                                          │
│  Variants { model: Quickshell.screens }                  │
│    └─ PanelWindow (una por monitor)                      │
│         └─ Rectangle { id: box }  ← el rectángulo animado│
│              ├─ ojos          (solo cerrado)             │
│              ├─ ColumnLayout  (header + ListView + input)│
│              └─ popup de comandos                        │
└──────────────────────────────────────────────────────────┘
```

**El puente con opencode.** `opencode run --format json` emite una línea JSON por evento. `handleOutput()` descarta las que no empiezan con `{`, parsea el resto, extrae el `sessionID` (del evento o de `part.sessionID`) y concatena todos los `type === "text"`.

**Cómo se lanza.** El comando va envuelto en `sh -c` y los argumentos viajan como parámetros posicionales (`"$0"`, `"$@"`), nunca interpolados. Un mensaje con comillas, backticks o `$` no rompe la shell. El binario se busca con `command -v opencode` y solo si no está en el `PATH` se usa `opencodeBin` como respaldo. El `exec` hace que el PID del proceso sea el de opencode, de modo que la señal de cancelación le llega directo.

**Cancelar.** El primer `Esc` con una petición en curso arma la cancelación (con un aviso junto al input) y un segundo `Esc` en menos de 1,5 s la ejecuta; el botón ■ y `/cancel` cancelan de inmediato. `cancel()` envía `SIGINT` (como `Ctrl+C`). Si el proceso sigue vivo 2 s después, se escala a `SIGTERM`. El texto que hubiera llegado se conserva y se marca como _(cancelado)_, sin sonido ni parpadeo.

**Persistencia.** Dos `FileView` en `~/.local/state/`: `meowko-session` guarda el `sessionID` y `meowko-prefs` guarda modelo, agente y directorio (JSON). Al arrancar se leen con `try/catch`; si faltan o están corruptos, se parte de cero.

**Por qué `StdioCollector`.** Espera a que el proceso termine, así que la respuesta aparece de golpe. Ver [Problemas conocidos](#problemas-conocidos).

**La geometría.** `progress` es un `real` de 0 a 1 con un `Behavior` de 220 ms. Todas las medidas del box se interpolan con él:

```
width:  root.closedW + (root.openW - root.closedW) * win.progress
height: root.closedH + (root.openH - root.closedH) * win.progress
```

Los ojos desaparecen al 33 % de la apertura (`Math.max(0, 1 - win.progress * 3)`). El contenido aparece recién entre el 60 % y el 100 % (`Math.max(0, (win.progress - 0.6) / 0.4)`), cuando el box ya casi tiene su tamaño final y no se nota el reescalado.

**Un widget por monitor.** `Variants` crea una `PanelWindow` por pantalla. Solo la que cumple `activeScreen === modelData.name` está abierta; las demás muestran los ojos.

---

## Requisitos

| Dependencia               | Para qué                   | Paquete en Arch                                      |
| ------------------------- | -------------------------- | ---------------------------------------------------- |
| Quickshell 0.3+           | el shell                   | `quickshell`                                         |
| `wlr-layer-shell`         | la capa flotante           | tu compositor (Hyprland, Sway, river, niri, wayfire) |
| `opencode`                | el backend                 | [instalación](https://opencode.ai)                   |
| PipeWire                  | `pw-play` para el aviso    | `pipewire-audio`                                     |
| `sound-theme-freedesktop` | el archivo `complete.oga`  | `sound-theme-freedesktop`                            |
| Inter                     | la tipografía              | `ttf-inter`                                          |
| Nerd Font                 | íconos de volumen y copiar | `ttf-jetbrains-mono-nerd`                            |

```sh
sudo pacman -S --needed pipewire-audio sound-theme-freedesktop ttf-inter ttf-jetbrains-mono-nerd
```

> **La Nerd Font es necesaria.** Los íconos se referencian por code point Unicode (`\uF028` volumen, `\uF026` mute, `\uF0C5` copiar, `\uF00C` check). Sin una fuente que los incluya no se dibuja nada y no aparece ningún error. Para no depender de ella, cambia `font.family: "JetBrainsMono Nerd Font"` por texto normal (`🔇`/`🔊`, `✓`/`⧉`).

---

## Instalación

```sh
git clone https://github.com/Gxstavo-dev/Meowko.git
cd Meowko
mkdir -p ~/.config/quickshell
cp -r meowko.qml components assets ~/.config/quickshell/
mv ~/.config/quickshell/meowko.qml ~/.config/quickshell/shell.qml
quickshell          # o el alias qs
```

Quickshell toma `~/.config/quickshell/shell.qml` como la configuración `default`. Si la instalas en otro lugar:

```sh
quickshell -p /ruta/a/shell.qml
```

`Cat.qml` vive en `components/` y los GIFs en `assets/`. Las rutas de `source` son relativas al `.qml` que las usa: desde `components/Cat.qml` apuntan a `../assets/...`, de modo que la carpeta completa se puede copiar tal cual.

> `shell.qml` está en `.gitignore` a propósito: es tu copia de trabajo. `meowko.qml` es la plantilla que se distribuye.

### Rutas y portabilidad

`meowko.qml` no trae rutas de usuario. Todo se resuelve en tiempo de ejecución con `StandardPaths.HomeLocation`:

| Propiedad        | Qué es                                                                      |
| ---------------- | --------------------------------------------------------------------------- |
| `sidFile.path`   | dónde se guarda el `sessionID`                                              |
| `prefsFile.path` | dónde se guardan modelo, agente y directorio                                |
| `workDir`        | directorio de trabajo de opencode (por defecto el home; cámbialo con `/cd`) |

**Dónde está opencode.** El widget ejecuta `command -v opencode` antes de cada comando, así que funciona con cualquier instalación que deje `opencode` en el `PATH`. `opencodeBin` es solo un respaldo para cuando Quickshell arranca con un `PATH` corto (típico al lanzarlo desde el autostart del compositor); por defecto apunta a `~/.cache/.bun/bin/opencode`. Si tu instalación está en otro lado, ajusta esa propiedad:

```qml
readonly property string opencodeBin: homePath + "/.local/share/npm-global/bin/opencode"
```

---

## Autostart

Elige **una** opción. No las combines: se pisan.

### Hyprland (config clásica)

En `~/.config/hypr/hyprland.conf`:

```ini
exec-once = pkill -x quickshell; sleep 0.3; quickshell
```

### Hyprland (config en Lua)

Hyprland 0.55+ permite escribir la configuración en Lua. En tu archivo de autostart, dentro del callback `hyprland.start`:

```lua
hl.on("hyprland.start", function()
    -- pkill evita duplicados si Hyprland recarga la config;
    -- el sleep le da tiempo al proceso viejo para morir.
    hl.exec_cmd("pkill -x quickshell 2>/dev/null; sleep 0.3; quickshell &")
end)
```

`hyprctl reload` **no** reinicia el widget: `hyprland.start` se dispara una sola vez, al arrancar Hyprland. Para reiniciarlo a mano:

```sh
hyprctl eval 'hl.exec_cmd("quickshell &")'
```

### Servicio systemd de usuario

Útil si quieres atarlo al ciclo de vida de la sesión, con reinicio automático ante un crash.

`~/.config/systemd/user/quickshell.service`:

```ini
[Unit]
Description=meowko panel widget
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/quickshell
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
```

```sh
systemctl --user daemon-reload
systemctl --user enable --now quickshell.service
journalctl --user -u quickshell.service -f
```

### Otros compositores

Con un `.desktop` en `~/.config/autostart/`:

```ini
[Desktop Entry]
Type=Application
Name=meowko
Exec=/usr/bin/quickshell
Terminal=false
```

### Verificar

```sh
pgrep -a -x quickshell         # debe listar una sola línea
hyprctl layers | grep meowko   # una capa por monitor (solo Hyprland)
```

---

## Estructura del proyecto

```
Meowko/
├── README.md
├── LICENSE                      # MIT © 2026 Gxstavo-dev
├── meowko.qml                   # plantilla: ShellRoot, estado, lógica, box animado
├── assets/
│   ├── gato_dormido.gif         # 145×125, 28 frames — opencode inactivo
│   ├── gato_tranquilo.gif       # 150×140, 34 frames — opencode trabajando
│   └── gato_icon.png            # ícono del README
├── components/
│   ├── Cat.qml                  # el gato (lee los GIFs de ../assets/)
│   ├── Eyes.qml                 # ojitos + parpadeo (solo mientras está cerrado)
│   ├── Header.qml               # sesión, "nuevo", volumen, cerrar
│   ├── MessageList.qml          # el ListView y el Connections a answered
│   ├── UserBubble.qml           # burbuja del mensaje del usuario
│   ├── AiMessage.qml            # respuesta markdown + botón de copiar
│   ├── ThinkingDots.qml         # los puntitos al "pensar"
│   └── InputBar.qml             # gato + campo de texto + placeholder
└── .gitignore                   # ignora shell.qml (tu copia de trabajo)
```

Los dos GIFs son pixel art con proporciones distintas. El alto de `Cat.qml` sale de la del tranquilo (`150:140`); `fillMode: PreserveAspectFit` ajusta el otro con un margen que a 26 px no se nota.

---

## Referencia de `meowko.qml`

Los comentarios del código están en inglés y explican el _porqué_, no el _qué_.

### Estado de `root`

```qml
property string activeScreen: ""   // nombre del monitor abierto
property string sessionId: ""      // sesión actual de opencode
property string model: ""          // "" = el de opencode
property string agent: ""          // "" = el de opencode
property string workDir: homePath  // cwd de opencode
property bool cancelled: false     // la petición en curso fue cancelada
property int pendingIndex: -1      // fila del placeholder de la IA
property bool muted: false
property bool unread: false        // respuesta sin leer
```

`unread` dispara el parpadeo. Se activa en `handleOutput()` **solo si** el widget está cerrado y se limpia en `onOpenChanged` al abrirlo.

`pendingIndex` guarda qué fila del modelo espera la respuesta. Hace falta porque los comandos pueden añadir filas mientras opencode trabaja, y "la última fila" dejaría de ser el placeholder.

### Funciones

| Función                         | Qué hace                                                                                       |
| ------------------------------- | ---------------------------------------------------------------------------------------------- |
| `clean(s)`                      | Quita códigos ANSI y las líneas de borde del TUI (`> … ·`)                                     |
| `setLast(s)`                    | Escribe en la fila `pendingIndex` del `ListModel`                                              |
| `sys(s)`                        | Añade una fila de aviso (salida de un comando)                                                 |
| `ocCommand(args)`               | Arma la invocación de opencode con `sh -c` y `command -v`                                      |
| `send(t)`                       | Añade los dos mensajes, arma los flags (`--model`, `--agent`, `--session`) y lanza             |
| `cancel()`                      | `SIGINT` al proceso; `SIGTERM` a los 2 s si sigue vivo                                         |
| `runCommand(line)`              | Resuelve un comando `/…`                                                                       |
| `list(...)` / `handleList(raw)` | Ejecuta `opencode models`, `agent list` o `session list` y muestra el resultado                |
| `handleOutput(raw)`             | Parsea el JSON, guarda la sesión, acumula el texto y dispara `answered()`, `ding()` y `unread` |
| `newChat()`                     | Limpia el modelo, la sesión y el archivo (avisa si hay una petición en curso)                  |
| `savePrefs()`                   | Guarda modelo, agente y directorio                                                             |
| `ding()`                        | Reproduce el sonido, salvo que esté silenciado                                                 |

### Los procesos

```qml
Process {
    id: proc
    workingDirectory: root.workDir
    environment: ({ NO_COLOR: "1", TERM: "dumb" })

    stdout: StdioCollector {
        onStreamFinished: root.handleOutput(text)
    }
    onExited: (code, status) => { /* si la IA quedó vacía, muestra el error */ }
}
```

`TERM: "dumb"` y `NO_COLOR` evitan que opencode emita secuencias de terminal. `lister` ejecuta los subcomandos de listado y `bell` reproduce el aviso; ambos son independientes de `proc`, así que nada bloquea la petición.

### `PanelWindow`

```qml
WlrLayershell.layer: WlrLayer.Overlay
WlrLayershell.namespace: "meowko"
WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
exclusionMode: ExclusionMode.Ignore
mask: Region { item: box }
```

`keyboardFocus` es condicional a propósito: con el widget cerrado no debe robar foco a otras aplicaciones.

### El `box`

El rectángulo que interpola entre cerrado y abierto. Aquí vive el parpadeo:

```qml
property real flash: 0
readonly property bool wantFlash: root.unread && !win.open
readonly property color flashBg: /* mezcla cBg → blanco según flash */
color: box.flash > 0 ? box.flashBg : root.cBg
```

`onWantFlashChanged` reinicia `flash` a 0, así que al abrir el widget el color vuelve al negro de golpe en vez de quedarse en un gris intermedio.

`radius: Math.min(24, width / 2, height / 2)` con `topLeftRadius` y `topRightRadius` en 0 lo dibuja como una pestaña redondeada solo por abajo.

### Los ojitos

Viven en `components/Eyes.qml`. Dos `Rectangle` de 5×8 px con `radius: 2.5`. La animación es una `SequentialAnimation` sobre `eyes.blink`: pausa de 3,8 s, cierra en 70 ms, abre en 90 ms, pausa de 400 ms y un segundo parpadeo. Solo corre con `running: !expanded`. El componente recibe el estado por propiedades (`blink`, `flash`, `progress`, `expanded`) y no conoce a `root` ni `win`.

### Encabezado

En `components/Header.qml`:

```
id-sesión   nuevo                        🔊   ✕
```

El ID de sesión usa `Layout.maximumWidth` y `elide: Text.ElideMiddle` para que los IDs largos no se coman el espacio de los botones. Un `Item { Layout.fillWidth: true }` empuja volumen y cierre contra el borde derecho. Las acciones (`nuevo`, silenciar, cerrar) se exponen como señales (`newRequested`, `muteRequested`, `closeRequested`) que `meowko.qml` conecta.

### Mensajes

El `delegate` vive en `components/MessageList.qml`, que arma cada fila con `UserBubble.qml`, `AiMessage.qml` y `ThinkingDots.qml`. Hay dos roles: `user` y `ai`. Cada fila decide su alto:

```qml
height: model.role === "user" ? userBubble.height
      : (model.text === "" ? 14 : aiMessage.bodyHeight + 24)
```

Los 24 px extra de las respuestas son para el ícono de copiar. El mensaje del usuario va en una burbuja a la derecha, limitada al 82 % del ancho de la fila:

```qml
width: Math.min(implicitWidth, row.width * 0.82)
```

La respuesta es `Text` plano a la izquierda con `textFormat: Text.MarkdownText`.

El placeholder de la IA es una fila con `text: ""`, y eso dispara los tres puntitos. `onCountChanged` lleva la vista al final; `meowko.qml` escucha `root.answered()` y avisa a `MessageList` por su señal `responded`, que sube tu mensaje al principio para que la respuesta entre por abajo.

### Copiar

```qml
onClicked: {
    Quickshell.clipboardText = model.text;
    copyBtn.copied = true;
    copyReset.restart();
}
```

`Quickshell.clipboardText` es una propiedad nativa y escribible, así que no hace falta `wl-copy`. Se usa una propiedad `copied` en lugar de reasignar `text`, porque asignar a un `Text` con binding lo rompe.

### Input, autocompletado y cancelación

`TextInput` dentro de un `Rectangle` de 38 px con `radius: 19`.

- `onAccepted`: si el texto empieza con `/` va a `runCommand()`; si no, a `send()`.
- `Keys.onTabPressed`: completa la primera sugerencia del popup.
- `Keys.onEscapePressed`: cierra el popup; si no hay popup y hay una petición en curso, el primer `Esc` arma la cancelación y el segundo la ejecuta; si no hay petición, cierra el widget.

El popup de comandos es un `Rectangle` flotante sobre el input. Calcula sus sugerencias filtrando `root.commands` por lo escrito, y solo aparece mientras no haya un espacio en el texto. El botón ■ junto al input solo es visible mientras `proc.running`.

---

## Referencia de `Cat.qml`

```qml
Item {
    id: cat
    property bool busy: false

    width: 26
    height: Math.round(width * 140 / 150)

    AnimatedImage {
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        loops: AnimatedImage.Infinite
        asynchronous: true
        cache: true
        smooth: false
        source: cat.busy ? "../assets/gato_tranquilo.gif" : "../assets/gato_dormido.gif"
    }
}
```

- **`smooth: false`** fuerza vecino más cercano. Sin esto, el reescalado a 26 px interpola y el pixel art se ve borroso.
- **No llames `gif.play()`.** En Qt 6.12 el método no existe y Quickshell lanza `TypeError: Property 'play' of object QQuickAnimatedImage is not a function`. `AnimatedImage` ya arranca solo con `loops: AnimatedImage.Infinite`.
- **`asynchronous: true`** evita que la carga bloquee el render.
- Las rutas son relativas al `.qml`: `Cat.qml` está en `components/`, así que los GIFs quedan en `../assets/`.
- Cambiar `source` reinicia la animación desde el frame 0, que es justo lo que se quiere al cambiar de estado.

> **Los nombres de archivo no pueden tener espacios.** QML resuelve `source` como URL y un espacio falla en silencio: el `AnimatedImage` queda en `Image.Error`, no dibuja nada y no aparece ningún error en consola. Usa guion bajo.

---

## Personalización

Medidas y paleta, agrupadas arriba en `root`:

```qml
readonly property int closedW: 44    // ancho cerrado
readonly property int closedH: 18    // alto cerrado
readonly property int openW: 600     // ancho abierto
readonly property int openH: 340     // alto abierto

readonly property color cBg: "#000000"
readonly property color cBubble: "#1c1c1e"
readonly property color cInput: "#141416"
readonly property color cText: "#f2f2f2"
readonly property color cAi: "#d0d0d0"
readonly property color cDim: "#6b6b70"
readonly property string fontFamily: "Inter"
```

**Tamaño del gato.** En el `Cat { ... }` de `components/InputBar.qml` (el pie del widget), cambia `width` (el alto sale de la proporción). Valores que funcionan: `20`, `26` (recomendado), `32`, `44`.

**Ritmo del parpadeo.** Son los `duration` de las animaciones `flash` (broadcast del `box` en `meowko.qml`) y `blink` (en `components/Eyes.qml`). Baja los `PauseAnimation` a 0 para un vaivén continuo.

**Sonido.** Cambia `soundFile`. Hay varios en `/usr/share/sounds/freedesktop/stereo/`: `complete.oga`, `bell.oga`, `message.oga`, `message-new-instant.oga`.

**Comandos propios.** Añade una entrada a `root.commands` (para el autocompletado) y un `case` en `runCommand()`.

**Gatos propios.** Reemplaza los GIFs. Cualquier tamaño funciona; el alto se ajusta solo.

---

## Problemas conocidos

**No hay streaming.** `StdioCollector.onStreamFinished` espera a que opencode termine, así que la respuesta aparece completa. Para ir viéndola hay que migrar a un parser incremental, `SplitParser` de `Quickshell.Io` con separador `\n`, que coincide con el formato JSON Lines. Antes de hacerlo conviene comprobar con `opencode run --format json` cuántos eventos `text` emite realmente: si solo emite uno por mensaje, el streaming no aportaría nada.

**Se lanza un proceso nuevo por mensaje.** Cada petición paga el arranque de opencode. Una alternativa es mantener `opencode serve` y hablarle por HTTP.

**Copiar se lleva el markdown crudo.** `model.text` guarda lo que vino de opencode, con `**` y backticks incluidos.

**`/cd` no valida la ruta.** Si el directorio no existe, el proceso no arranca y verás "(sin respuesta, código …)".

**`/agent` no valida el nombre.** Un agente inexistente falla al enviar el siguiente mensaje. Usa `/agents` para ver los válidos.

**`/agents` y `/sessions` muestran la salida tal cual.** El formato de esos subcomandos lo decide opencode.

**El historial no se recupera.** Con `/session <id>` o al reiniciar el widget, opencode recuerda la conversación pero el widget no la muestra.

**`Inter` es opcional.** Si no está, Qt usa la fuente por defecto y se ve distinto, pero no se rompe. La Nerd Font sí es obligatoria (ver [Requisitos](#requisitos)).

**Sin `onExited` en `bell`.** Si `pw-play` no está instalado, el aviso falla en silencio.

**Solo Wayland.** `wlr-layer-shell` no existe en X11.

**Warning de ABI de Qt.** Si al arrancar aparece:

```
Quickshell was built against Qt 6.11.2 but the system has updated to Qt 6.12.0
without rebuilding the package. This is likely to cause crashes, so the
quickshell package must be rebuilt.
```

no es un problema de este repo: el paquete de Quickshell quedó desactualizado respecto al Qt del sistema. Se arregla reconstruyéndolo (`yay -S quickshell`). Mientras tanto el widget suele funcionar, pero si hay crashes aleatorios, empieza por ahí.

---

## Roadmap

Pendiente:

- [x] Reorganizar el código: `assets/` para los GIFs y `components/` para cada componente QML
- [ ] Mostrar el modelo activo
- [ ] Cambiar de modelo (`/model`, `/models`)
- [ ] Comandos con `/` y autocompletado
- [ ] Cancelar una petición (`Esc` dos veces, ■, `/cancel`)
- [ ] Elegir agente (`/agent`)
- [ ] Cambiar de sesión (`/sessions`, `/session`)
- [ ] Directorio de trabajo (`/cd`)
- [ ] Detectar opencode automáticamente con `command -v`
- [ ] Streaming con `SplitParser`
- [ ] Mostrar avisos de uso excedido y de reintento (p. ej. "Free usage exceeded… retrying in 8m 32s")
- [ ] Mostrar el historial al retomar una sesión
- [ ] Entrada multilínea (`Shift+Enter`) e historial con la flecha arriba
- [ ] Bloques de código con botón de copiar propio y copiar sin markdown crudo
- [ ] Adjuntar archivos
- [ ] Atajo global para abrir y cerrar el widget
- [ ] Arranque más rápido (servidor persistente en lugar de un proceso por mensaje)

---

## Licencia

MIT © 2026 [Gxstavo-dev](https://github.com/Gxstavo-dev). Ver [LICENSE](LICENSE).
