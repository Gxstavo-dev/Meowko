<div align="center">

# meowko

**Un widget de Wayland para chatear con [opencode](https://opencode.ai), en el panel superior.**

Un gatito que duerme cuando opencode está inactivo, se despierta mientras contesta, y te avisa con un parpadeo cuando la respuesta llegó.

</div>

---

## Índice

- [Qué hace](#qué-hace)
- [Demo](#demo)
- [Cómo funciona por dentro](#cómo-funciona-por-dentro)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Autostart en Arch + Hyprland](#autostart-en-arch--hyprland)
- [Sobre Lua](#sobre-lua)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Referencia de `shell.qml`](#referencia-de-shellqml)
- [Referencia de `Cat.qml`](#referencia-de-catqml)
- [Personalización](#personalización)
- [Problemas conocidos](#problemas-conocidos)
- [Licencia](#licencia)

---

## Qué hace

Un botón flotante anclado al borde superior de la pantalla. Cerrado es una barrita negra de 44×18 px con dos ojitos que parpadean de vez en cuando, como si esperara. Lo clickeás y se abre una burbuja negra de 600×340 px con la conversación.

Dentro:

| Acción                                 | Resultado                                                      |
| -------------------------------------- | -------------------------------------------------------------- |
| Escribís algo y dá `Enter`             | Se envía a `opencode run` y aparecen tres puntitos parpadeando |
| Llega la respuesta                     | El texto aparece, suena un aviso, y el input se limpia         |
| Hay respuesta y el widget está cerrado | La barrita parpadea de negro a blanco muy despacio             |
| Abrís el widget                        | El foco salta solo al input y el parpadeo se corta             |
| Click en el ícono de volumen           | Silencia el aviso (no afecta el parpadeo)                      |
| Click en el ícono de copiar            | Copia la respuesta al portapapeles y muestra un ✓ por 1,2 s    |
| Click en "nuevo"                       | Borra la conversación y la sesión guardada                     |
| `Escape`                               | Cierra el widget                                               |

El gato junto al input indica el estado de opencode: **dormido** si no está haciendo nada, **tranquilo** si está trabajando. Es el mismo estado que alimenta los puntitos de "pensando".

### Dos detalles de diseño

**La capa.** Usa `wlr-layer-shell` en `WlrLayer.Top` con `exclusionMode: Ignore`, así que flotan sobre todo sin reservar espacio en la barra del compositor. El `mask: Region { item: box }` recorta la superficie invisible, para que el clicks que no están sobre el widget no se intercepten.

**El parpadeo de alerta.** No alterna entre blanco y negro de golpe: interpola. `flash` sube y baja con `Easing.InOutSine` y el color del fondo se calcula mezclando `cBg` hacia blanco según ese valor. Los ojitos invierten a negro con la misma variable, porque si no desaparecerían sobre el fondo blanco. El ciclo completo dura 8 s: 2,6 s de fundido, 1,4 s de pausa, 2,6 s de vuelta, 1,4 s de pausa.

---

## Cómo funciona por dentro

No hay servidor, ni TUI, ni terminal oculta. El widget habla directo con el binario de opencode por JSON.

```
┌─ shell.qml (ShellRoot) ──────────────────────────────────┐
│                                                         │
│  Process { id: proc }                                   │
│    └─ sh -c 'exec opencode run --format json ...'       │
│         └─ stdout ─► StdioCollector ─► handleOutput()    │
│              └─ parsea cada línea JSON                  │
│                   ├─ sessionID ─► FileView (a disco)    │
│                   └─ type:"text" ─► ListModel chat       │
│                                                         │
│  Process { id: bell }  ─► pw-play complete.oga           │
│                                                         │
│  Variants { model: Quickshell.screens }                 │
│    └─ PanelWindow (una por monitor)                     │
│         └─ Rectangle { id: box }  ← el rectángulo animado│
│              ├─ ojos       (solo cerrado)                │
│              ├─ ColumnLayout (header + ListView + input) │
│              └─ Cat       (dentro del input)            │
└─────────────────────────────────────────────────────────┘
```

**El puente con opencode.** `opencode run --format json` emite una línea JSON por evento. `handleOutput()` las filtra con `startsWith("{")`, las parsea, saca el `sessionID` (either del evento o de `part.sessionID`) y concatena todos los `type === "text"` en un string.

**La persistencia de sesión.** Un `FileView` en `~/.local/state/meowko-session` guarda el `sessionID`. Al arrancar, `Component.onCompleted` lo lee con `try/catch`, y con `--session "$2"` opencode retoma la conversación anterior. Si el archivo está corrupto, cae a `""` y arranca una sesión nueva.

**Por qué `StdioCollector`.** El `onStreamFinished` de `StdioCollector` espera a que el proceso termine, así que **no hay streaming**: la respuesta completa aparece de golpe. Ver [Problemas conocidos](#problemas-conocidos).

**La geometría.** `progress` es un `real` de 0 a 1 con `Behavior` de 220 ms. Todas las medidas del box se interpolan con él:

```qml
width:  root.closedW + (root.openW - root.closedW) * win.progress
height: root.closedH + (root.openH - root.closedH) * win.progress
```

Los ojos usan `opacity: Math.max(0, 1 - win.progress * 3)`, o sea desaparecen al 33% de la apertura. El contenido aparece más tarde, con `Math.max(0, (win.progress - 0.6) / 0.4)`: recién se ve del 60% al 100%, que es cuando el box ya tiene el tamaño final y no se nota el reescalado.

**Un widget por monitor.** `Variants` crea una `PanelWindow` por pantalla, todas superpuestas. Solo la que cumple `activeScreen === modelData.name` tiene `open: true`. El resto quedan cerradas mostrando los ojos. `mask: Region` recorta cada una.

---

## Requisitos

| Dependencia               | Para qué                   | Paquete en Arch                                      |
| ------------------------- | -------------------------- | ---------------------------------------------------- |
| Quickshell 0.3+           | el shell                   | `quickshell`                                         |
| `wlr-layer-shell`         | la capa flotante           | tu compositor (Hyprland, Sway, river, niri, wayfire) |
| `opencode`                | el backend                 | [docs de instalación](https://opencode.ai)           |
| PipeWire                  | `pw-play` para el aviso    | `pipewire-audio`                                     |
| `sound-theme-freedesktop` | el archivo `complete.oga`  | `sound-theme-freedesktop`                            |
| Inter                     | la tipografía              | `ttf-inter`                                          |
| Nerd Font                 | íconos de volumen y copiar | `ttf-jetbrains-mono-nerd`                            |

```bash
sudo pacman -S --needed pipewire-audio sound-theme-freedesktop ttf-inter
```

> **La Nerd Font es necesaria.** Los íconos se referencian por code point Unicode (`\uF028` volumen, `\uF026` mute, `\uF0C5` copiar, `\uF00C` check). Sin una fuente que los tenga, no se dibuja nada y no sale ningún error. Si no querés depender de eso, en `shell.qml` cambiá `font.family: "JetBrainsMono Nerd Font"` por texto normal: `🔇`/`🔊` y `✓`/`⧉`.

---

## Instalación

```bash
git clone https://github.com/TU-USUARIO/meowko.git
cp meowko/shell.qml meowko/Cat.qml meowko/*.gif ~/.config/quickshell/
```

Quickshell detecta `~/.config/quickshell/shell.qml` como la configuración `default`, así que alcanza con:

```bash
quickshell          # o el alias qs
```

Si lo instalás en otro lado:

```bash
quickshell -p ~/dotfiles/quickshell/shell.qml
```

### Rutas y portabilidad

`shell.qml` **no trae rutas hardcodeadas**: todo se resuelve en runtime con `Qt.homePath`, que devuelve el home del usuario que ejecuta el widget. Funcionan igual para vos, para el binario que lo corra o para cualquiera que clone el repo:

| Línea | Qué es                                              |
| ----- | --------------------------------------------------- |
| 52    | `opencodeBin` — binario de opencode                 |
| 98    | `sidFile.path` — dónde se guarda el `sessionID`     |
| 256   | `proc.workingDirectory` — el cwd del proceso        |

> **Única asunción externa: dónde vive opencode.** `opencodeBin` apunta a `Qt.homePath + "/.cache/.bun/bin/opencode"`, o sea, asume que opencode se instaló con **bun** (instalación por defecto recomendada en [opencode.ai](https://opencode.ai)). Si lo instalaste por otra vía (npm global, cargo, binario manual, etc.) la línea 52 se ajusta al path real, por ejemplo `Qt.homePath + "/.local/share/npm-global/bin/opencode"` o una ruta literal. Es solo texto — quickshell le pasa la ruta a `sh -c` tal cual.

---

## Autostart en Arch + Hyprland

Tu setup usa `hyprland.lua` (Hyprland 0.55+ escribe la config en Lua), así que el
widget se lanza desde tu propio módulo de autostart.

### Opción A — tu `modules/autostart.lua` (la que usás)

En `~/.config/hypr/modules/autostart.lua`, dentro del callback `hyprland.start`:

```lua
---@diagnostic disable: undefined-global

hl.on("hyprland.start", function()
    -- ... tus otros exec_cmd ...

    -- meowko: widget de chat para opencode.
    -- pkill primero evita duplicados si Hyprland recarga la config; el
    -- `sleep` le da tiempo a que el proceso viejo muera antes de arrancar.
    hl.exec_cmd("pkill -x quickshell 2>/dev/null; sleep 0.3; quickshell -p $HOME/.config/quickshell/shell.qml &")
end)
```

Tres detalles de esa línea:

| Parte                 | Por qué                                                                                     |
| --------------------- | ------------------------------------------------------------------------------------------- |
| `pkill -x quickshell` | Si ya había una instancia, la mata antes de crear otra                                      |
| `sleep 0.3`           | Le da tiempo al proceso viejo a morir, si no queda huérfano                                 |
| `&` al final          | `hl.exec_cmd` no bloquea; sin el `&` igual funciona, pero el `pkill`+yaml se encadenan raro |

**`hyprctl reload` no lo reinicia.** El evento `hyprland.start` se dispara una sola vez,
al arrancar Hyprland. Un reload solo vuelve a leer la config, así que para reiniciar el
widget a mano:

```bash
hyprctl eval 'hl.exec_cmd("quickshell -p ~/.config/quickshell/shell.qml &")'
```

Verificá que quedó una sola instancia:

```bash
pgrep -a -x quickshell      # debe listar una sola línea
hyprctl layers | grep meowko   # una capa por monitor
```

### Opción B — servicio systemd de usuario

Alternativa si preferís el widget atado al ciclo de vida de la sesión y con
reinicio automático ante crash. **No combines las dos**, se pisan.

```bash
mkdir -p ~/.config/systemd/user
```

`~/.config/systemd/user/quickshell.service`:

```ini
[Unit]
Description=meowko panel widget
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/quickshell -p %h/.config/quickshell/shell.qml
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now quickshell.service
systemctl --user status quickshell.service
journalctl --user -u quickshell.service -f
```

`%h` lo expande systemd a tu HOME, así el unit no depende de tu username.

### Opción C — `.desktop` en autostart

Para cuando usés un compositor sin Hyprland:

```bash
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/quickshell.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=meowko
Exec=/usr/bin/quickshell -p %h/.config/quickshell/shell.qml
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
```

### Nota sobre Hyprland 0.55+ y la sintaxis de dispatch

Si en algún momento querés dispararlo desde un keybind, la sintaxis de `dispatch` cambió.
La forma vieja da error:

```
$ hyprctl dispatch exec "quickshell -p ~/... &"
error: ')' expected near 'pkill'
```

Usá `hl.exec_cmd` dentro de `hyprctl eval`:

```bash
hyprctl eval 'hl.exec_cmd("quickshell -p ~/.config/quickshell/shell.qml &")'
```

Y en un keybind de `hyprland.lua`:

```lua
hl.bind("SUPER + Q", function()
  hl.exec_cmd("quickshell -p $HOME/.config/quickshell/shell.qml &")
end)
```

### Nota sobre Hyprland y `wlr-layer-shell`

Hyprland implementa `wlr-layer-shell`, así que `WlrLayershell.layer` y
`exclusionMode` funcionan sin configuración extra. El widget queda en la capa
overlay: flota sobre todo y no reserva espacio en la barra.

Para confirmar que está mapeado:

```bash
hyprctl layers | grep meowko
# Layer 5601...: xywh: 383 0 600 340, namespace: meowko, pid: ...
```

Una capa por monitor, todas con el namespace `meowko`.

---

## Sobre Lua

Hay **dos Lua distintos** en juego y conviene no confundirlos:

|                       | Qué es                                                     | Dónde                                  |
| --------------------- | ---------------------------------------------------------- | -------------------------------------- |
| **Hyprland en Lua**   | La config del compositor, `hyprland.lua` + `modules/*.lua` | `~/.config/hypr/`                      |
| **Quickshell en Lua** | Variante de Quickshell escrita en Lua, QML reducido        | build aparte, no es el paquete de Arch |

**Este repo es QML.** Solo usa el primer Lua, y únicamente para lanzar el widget.
El widget en sí (`shell.qml`, `Cat.qml`) sigue siendo QML, que es lo que entiende
el `/usr/bin/quickshell` del paquete de Arch:

```
$ ldd /usr/bin/quickshell | grep -c lua
0
```

No hay interpreter de Lua embebido. La variante Lua de Quickshell se compila aparte
desde el repo de upstream y produce otro binario. Si algún día la querés, el trabajo
no es un find-and-replace:

| Concepto    | QML (esto)                     | Variante Lua            |
| ----------- | ------------------------------ | ----------------------- |
| Layout      | `RowLayout` / `ColumnLayout`   | igual, es el mismo QML  |
| Propiedades | `property bool unread`         | campos de `QsObject`    |
| Animaciones | `SequentialAnimation` en línea | `Quickshell.animations` |
| Procesos    | `Process { id: proc }`         | `Process` con `run()`   |
| Eventos     | `onClicked:`                   | `on_clicked()`          |

Como el árbol de widgets (`Rectangle`, `Text`, `ListView`, `AnimatedImage`) **es el
mismo QML** en ambas variantes, la parte visual se porta casi tal cual. Lo que cambia
es el andamiaje: declaración de propiedades, bindings, y el sistema de animaciones.

Mientras tanto, `quickshell reload` sobre el QML actual funciona y es instantáneo.

## Estructura del proyecto

```
meowko/
├── README.md
├── LICENSE             # MIT © 2026 Gxstavo-dev
├── shell.qml            # 857 líneas — ventana, layout, lógica, clipboard
├── Cat.qml              #  61 líneas — el gato
├── gato_dormido.gif     # 145×125, 28 frames, 77 KB — opencode inactivo
├── gato_tranquilo.gif   # 150×140, 34 frames, 89 KB — opencode trabajando
└── demo.gif             # (opcional) la captura para este README
```

Los dos GIFs son pixel art con proporciones distintas, y el alto de `Cat.qml` sale de la del tranquilo (`150:140`). `fillMode: PreserveAspectFit` hace que el que no coincide se ajuste con un margen chico, invisible a 26 px.

---

## Referencia de `shell.qml`

Todo el código está comentado en inglés. Los comentarios explican el _porqué_, no el _qué_: por ejemplo por qué el comando va envuelto en `sh -c`, por qué el blink interpola el color en vez de alternarlo, o por qué `keyboardFocus` es condicional.

### Estado de root

```qml
property string activeScreen: ""                              // nombre del monitor abierto
property string sessionId: ""                                 // sesión actual de opencode
property bool muted: false                                    // silence el aviso
property bool unread: false                                   // respuesta sin leer
readonly property string soundFile: ".../complete.oga"
readonly property string opencodeBin: ".../opencode"
```

`unread` es lo que dispara el parpadeo. Se pone en `true` en `handleOutput()` **solo si** `activeScreen === ""`, o sea que si tenés el widget abierto no parpadea. Se limpia en `onOpenChanged` al abrir.

### Funciones

| Función             | Qué hace                                                                                      |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `clean(s)`          | Saca los códigos ANSI y filtra las líneas del borde del TUI (`> … ·`)                         |
| `setLast(s)`        | Escribe en la última fila del `ListModel` (el placeholder de la IA)                           |
| `handleOutput(raw)` | Parsea el JSON, guarda la sesión, acumula el texto, dispara `answered()`, `ding()` y `unread` |
| `send(t)`           | Agrega los dos mensajes al modelo y arma el comando                                           |
| `newChat()`         | Limpia el modelo, la sesión y el archivo (aborta si `proc.running`)                           |
| `ding()`            | Reproduce el sonido, salvo que esté muteado                                                   |

### Los dos procesos

```qml
Process {
    id: proc
    workingDirectory: Qt.homePath
    environment: ({ NO_COLOR: "1", TERM: "dumb" })

    stdout: StdioCollector {
        onStreamFinished: root.handleOutput(text)
    }
    onExited: (code, status) => { /* si la IA quedó vacía, muestra el error */ }
}
```

`TERM: "dumb"` y `NO_COLOR` evitan que opencode emita secuencias de terminal. El comando va envuelto en `sh -c` con `"$0"`, `"$1"`, `"$2"` en vez de interpolar strings: así un mensaje con comillas o `$` no rompe la shell.

`bell` es un `Process` vacío al que solo se le asigna `command` y `running` al sonar. Al ser independiente, el aviso no bloquea el proceso de opencode.

### `PanelWindow`

```qml
WlrLayershell.layer: WlrLayer.Top
WlrLayershell.namespace: "meowko"
WlrKeyboardFocus.OnDemand: solo cuando está abierto
exclusionMode: ExclusionMode.Ignore
mask: Region { item: box }
```

`keyboardFocus` es condicional a propósito: con el widget cerrado el layer no debería robar foco de otras apps.

### El `box`

El rectángulo que interpola entre cerrado y abierto. Acá vive el parpadeo:

```qml
property real flash: 0
readonly property bool wantFlash: root.unread && !win.open
readonly property color flashBg: /* mezcla cBg → blanco según flash */
color: box.flash > 0 ? box.flashBg : root.cBg
```

`onWantFlashChanged` resetea `flash` a 0, así al abrir el widget el color vuelve al negro de golpe en vez de quedar en un gris intermedio.

El `radius: Math.min(24, width / 2, height / 2)` con `topLeftRadius` y `topRightRadius` en 0 hace que se vea como una pestaña redondeada solo por abajo.

### Los ojitos

Dos `Rectangle` de 5×8 px con `radius: 2.5`. La animación de parpadeo es una `SequentialAnimation` sobre `eyes.blink`: pausa 3,8 s, cierra 70 ms, abre 90 ms, pausa 400 ms, repite. Corre solo con `running: !win.open`.

### Header

```
id-sesión   nuevo          🔊   ✕
```

El `Text` del `sessionID` usa `Layout.maximumWidth: 240` con `elide: Text.ElideMiddle`, así los IDs largos se recortan por el medio sin comerse el espacio de los botones. El `Item { Layout.fillWidth: true }` entre "nuevo" y el volumen empuja los dos íconos juntos contra el borde derecho.

### Mensajes

Cada fila es un `delegate` que decide su alto:

```qml
height: model.role === "user" ? bubble.height
        : (model.text === "" ? 14 : aiText.height + 24)
```

Los 24 px extra son para el ícono de copiar. Tu mensaje va en burbuja redondeada a la derecha, con el ancho limitado al 82% del row:

```qml
width: Math.min(implicitWidth, row.width * 0.82)
```

La respuesta es `Text` plano a la izquierda con `textFormat: Text.MarkdownText` y `lineHeight: 1.25`. Los links salen en blanco.

El placeholder de la IA es un mensaje con `text: ""`, y eso es lo que dispara los tres puntitos. `onCountChanged` lleva la vista al final; un `Connections` a `root.answered()` sube tu mensaje al principio de la vista para que la respuesta entre por abajo.

### Copiar

```qml
onClicked: {
    Quickshell.clipboardText = model.text;
    copyBtn.copied = true;
    copyReset.restart();
}
```

`Quickshell.clipboardText` es una propiedad nativa (writable, con su `clipboardTextChanged`), así que no hace falta `wl-copy`. El `Timer` de 1.2 s vuelve el ícono a `\uF0C5`. Se usa una property `copied` en vez de reasignar `text`, porque asignar a un `Text` con binding lo rompe.

### Input

`TextInput` dentro de un `Rectangle` de 38 px con `radius: 19`. `onAccepted` manda y limpia; `Keys.onEscapePressed` cierra. El placeholder `"pregunta algo…"` es un `Text` hijo que se muestra cuando `input.text === ""`, con `font: input.font` para que herede la tipografía.

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
        source: cat.busy ? "gato_tranquilo.gif" : "gato_dormido.gif"
    }
}
```

- **`smooth: false`** fuerza vecino-nearest. Sin esto el reescalado a 26 px interpola y el pixel art se ve borroso.
- **No llames `gif.play()`.** En Qt 6.12 el método no existe y Quickshell tira
  `TypeError: Property 'play' of object QQuickAnimatedImage is not a function`.
  `AnimatedImage` ya arranca solo cuando `loops: AnimatedImage.Infinite`.
- **`asynchronous: true`** evita que la carga bloquee el render.
- Las rutas son relativas al `.qml`, así que los GIFs tienen que estar en la misma carpeta.
- Cambiar `source` reinicia la animación desde el frame 0, que es justo lo que querés al cambiar de estado.

> **Los nombres de archivo no pueden tener espacios.** QML resuelve `source` como URL, y un espacio ahí falla en silencio: el `AnimatedImage` queda en `Image.Error`, no dibuja nada y no aparece ningún error en la consola. Renombrá los archivos con guion bajo.

El alto se calcula de la proporción del GIF tranquilo (`150:140`). El dormido es `145:125`, y `PreserveAspectFit` lo deja con un margen vertical que no se nota a este tamaño.

---

## Personalización

Medidas y paleta, agrupadas arriba en root (`shell.qml:55-80`):

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

**Tamaño del gato** — `Cat.qml:24` y `shell.qml:806`:

```qml
Cat {
    busy: proc.running
    width: 26          // el alto sale de la proporción
}
```

Valores que funcionan: `20` (muy tiny), `26` (recomendado), `32`, `44`.

**Ritmo del parpadeo** — los `duration` en `shell.qml:386-406`. Bajá los `PauseAnimation` a 0 para un vaivén continuo sin pausas.

**Sonido** — cambiá `soundFile`. Hay varios en `/usr/share/sounds/freedesktop/stereo/`: `complete.oga`, `bell.oga`, `message.oga`, `message-new-instant.oga`.

**Gatos propios** — reemplazá los GIFs. Cualquier tamaño funciona, el alto se ajusta solo.

---

## Problemas conocidos

**No hay streaming.** `StdioCollector.onStreamFinished` espera a que opencode termine, así que la respuesta aparece completa de golpe. Para token a token hay que migrar a un parser incremental: `DataStreamParser` o `SplitParser` de `Quickshell.Io`, con `SplitParser` en modo `\n` que coincide con el formato JSON Lines de opencode.

**La ruta de opencode.** `opencodeBin` asume una instalación vía bun (`~/.cache/.bun/bin/opencode`). Si la tuya es distinta, ver [Rutas y portabilidad](#rutas-y-portabilidad). Es lo único que puede requerir un toque al instalar en otra máquina.

**Copiar se lleva el markdown crudo.** `model.text` guarda lo que vino de opencode, con `**` y backticks incluidos.

**`Inter` es opcional de verdad.** Si no la tenés, Qt cae a la fuente por defecto y se ve distinto pero no se rompe. La Nerd Font en cambio sí es obligatoria, ver [Requisitos](#requisitos).

**Sin `onExited` en `bell`.** Si `pw-play` no está instalado, el aviso falla en silencio.

**Solo Wayland.** `WlrLayerShell` no existe en X11.

**Warning de ABI de Qt.** Si al arrancar ves esto:

```
Quickshell was built against Qt 6.11.2 but the system has updated to Qt 6.12.0
without rebuilding the package. This is likely to cause crashes, so the
quickshell package must be rebuilt.
```

No es culpa de este repo, es el paquete de Arch desactualizado contra el Qt del
sistema. Se arregla reconstruyendo:

```bash
yay -S quickshell
```

El widget anda igual mientras tanto, pero si te crashea aleatoriamente, empezá por acá.

---

## Licencia

MIT © 2026 [Gxstavo-dev](https://github.com/Gxstavo-dev) — ver [LICENSE](LICENSE).
