import QtQuick
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "components"

// ============================================================================
// meowko — plantilla generalizada, una widget Wayland/panel-shell que chatea
// con opencode.
//
// Este archivo es la versión portátil: NO trae ningún path hardcodeado y
// funciona para cualquier usuario. Copialo a tu config y editalo libremente:
//
//     cp -r meowko.qml components assets ~/.config/quickshell/
//     mv ~/.config/quickshell/meowko.qml ~/.config/quickshell/shell.qml
//     quickshell              # o el alias qs
//
// Estructura:
//
//     meowko.qml        -> ShellRoot, estado, lógica de opencode, ventana
//     components/       -> Cat, Eyes, Header, MessageList, UserBubble,
//                          AiMessage, ThinkingDots, InputBar
//     assets/           -> los GIFs del gato y el ícono
//
// Closed: a 44x18 black bar with two blinking eyes, pinned to the top edge of
// the screen. Click it and it expands into a 600x340 chat bubble.
//
// The whole thing is a single ShellRoot: it spawns `opencode run` as a child
// process, parses its JSON stream, and feeds a ListModel that the ListView
// renders. No TUI, no terminal, no HTTP server.
//
// Full docs: README.md
// ============================================================================

ShellRoot {
    id: root

    // ---------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------

    // Name of the screen whose window is currently expanded. Empty string
    // means closed on every monitor. This is the single source of truth for
    // open/closed state — `win.open` further down is derived from it, not
    // the other way around.

    property string activeScreen: ""
    property string sessionId: ""

    // When true, ding() is a no-op. Only silences the sound — the blinking
    // alert still runs, since that is a visual cue with a different purpose.

    property bool muted: false
    readonly property string soundFile: "/usr/share/sounds/freedesktop/stereo/complete.oga"

    // True when a response arrived while the widget was closed. Drives the
    // black/white blink animation. Cleared the moment the user opens it.

    property bool unread: false

    // Emitted once a full response has been written into the model. The
    // ListView listens for it to scroll your message back to the top, so the
    // answer enters the viewport from below.

    signal answered

    // ---------------------------------------------------------------------
    // CONFIGURACIÓN — lo único que podés llegar a tocar al instalarlo
    // ---------------------------------------------------------------------
    //
    // homePath se resuelve solo: es el home del usuario que corre la widget
    // (vía StandardPaths.HomeLocation, sin el scheme file://). No lo edites.
    //
    // opencodeBin asume que opencode se instaló con bun (~/.cache/.bun/bin).
    // Si lo instalaste por otra vía (npm global, cargo, binario manual),
    // cambiá este path, p. ej.:
    //     homePath + "/.local/share/npm-global/bin/opencode"
    //
    // El resto de rutas (sidFile, workingDirectory) también deriva de
    // homePath y no necesita toques.

    readonly property string homePath: String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")

    readonly property string opencodeBin: homePath + "/.cache/.bun/bin/opencode"

    // ---------------------------------------------------------------------
    // Geometry
    //
    // `closed*` is the resting bar, `open*` is the expanded bubble. Every
    // dimension in the UI is interpolated between the two using
    // `win.progress` (0 -> 1), which is why nothing hard-cuts mid-transition.
    // ---------------------------------------------------------------------

    readonly property int closedW: 44
    readonly property int closedH: 18
    readonly property int openW: 600
    readonly property int openH: 340

    // ---------------------------------------------------------------------
    // Palette — dark and near-neutral. cDim is the resting color for anything
    // interactive; cText / cAi are the two text weights (yours vs the model's).
    // ---------------------------------------------------------------------

    readonly property color cBg: "#000000"
    readonly property color cBubble: "#1c1c1e"
    readonly property color cInput: "#141416"
    readonly property color cText: "#f2f2f2"
    readonly property color cAi: "#d0d0d0"
    readonly property color cDim: "#6b6b70"
    readonly property string fontFamily: "Inter"

    // ---------------------------------------------------------------------
    // Data
    // ---------------------------------------------------------------------

    // Every message in the conversation, two roles: "user" and "ai".
    // An "ai" entry with text === "" is the thinking placeholder — that empty
    // string is what swaps the pulsing dots in for the real response.

    ListModel {
        id: chat
    }

    // Persists the session ID across restarts. blockLoading makes text()
    // available synchronously inside Component.onCompleted, so the session is
    // restored before the first prompt instead of racing it.

    FileView {
        id: sidFile
        path: homePath + "/.local/state/meowko-session"
        blockLoading: true
    }

    // Restore the last session on startup. A missing or corrupt file falls back
    // to "" and starts a fresh conversation rather than throwing.

    Component.onCompleted: {
        try {
            root.sessionId = sidFile.text().trim();
        } catch (e) {
            root.sessionId = "";
        }
        console.log("sesión cargada:", root.sessionId === "" ? "(ninguna)" : root.sessionId);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    // Fallback text extraction, used only when JSON parsing yields nothing.
    // opencode can emit TUI decorations (ANSI color codes, and `> ...` border
    // lines), so strip both to avoid rendering garbage.
    function clean(s) {
        return s.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").split("\n").filter(l => !/^\s*>\s*\S+\s*·/.test(l)).join("\n").trim();
    }

    // Overwrite the last row in the model — i.e. the empty "ai" placeholder
    // that send() appended — with the finished response.
    function setLast(s) {
        const i = chat.count - 1;
        if (i < 0)
            return;
        chat.setProperty(i, "text", s);
    }

    // Start over: clear the transcript and the stored session. Refuses while
    // opencode is working, so you cannot orphan a running process.
    function newChat() {
        if (proc.running)
            return;
        chat.clear();
        root.sessionId = "";
        sidFile.setText("");
    }

    // ---------------------------------------------------------------------
    // opencode bridge
    // ---------------------------------------------------------------------

    // Parse the whole stdout buffer. `opencode run --format json` emits one
    // JSON object per line (JSON Lines), so we skip anything not starting with
    // "{" and accumulate every `type === "text"` chunk into one string.
    //
    // The session ID arrives either at the top level or nested under `part`,
    // depending on the event shape, so check both.
    //
    // NOTE: this only runs once the process exits (see StdioCollector below),
    // which means the response appears all at once rather than streaming.

    function handleOutput(raw) {
        let text = "";
        let found = "";

        for (const line of raw.split("\n")) {
            const t = line.trim();
            if (!t.startsWith("{"))
                continue;
            let o;
            try {
                o = JSON.parse(t);
            } catch (e) {
                continue;
            }
            const sid = o.sessionID || (o.part && o.part.sessionID);
            if (sid)
                found = sid;
            if (o.type === "text" && o.part && o.part.text)
                text += o.part.text;
        }

        if (found !== "" && found !== root.sessionId) {
            root.sessionId = found;
            sidFile.setText(found);
            console.log("sesión guardada:", found);
        }

        // Persist a newly discovered session so the next run can resume it.

        const result = text.trim() !== "" ? text.trim() : root.clean(raw);
        // Fall back to scraping raw output if no text events were found.
        // Then: publish the message, notify listeners, play the sound, and
        // flag the blink — but only if the widget is closed. If the user is
        // already looking at it, blinking would be noise.

        if (result !== "") {
            root.setLast(result);
            root.answered();
            root.ding();
            root.unread = root.activeScreen === "";
        }
    }

    // Play the notification sound through PipeWire. A no-op when muted.

    function ding() {
        if (root.muted)
            return;
        bell.command = ["pw-play", root.soundFile];
        bell.running = true;
    }

    // Dedicated process for the sound, kept separate from `proc` so playing a
    // notification never blocks or interferes with the opencode run.

    Process {
        id: bell
    }

    // Append both messages optimistically, then launch opencode.
    // Appending the empty "ai" row immediately is what makes the thinking
    // dots appear right away instead of after the first byte arrives.

    function send(t) {
        console.log("send llamado con:", t, "running:", proc.running);
        if (proc.running || t.trim() === "")
            return;

        chat.append({
            role: "user",
            text: t
        });
        chat.append({
            role: "ai",
            text: ""
        });   // empty text => render the thinking dots

        // The command is wrapped in `sh -c` and the arguments are passed as
        // positional params ($0, $1, $2) rather than interpolated into the
        // string. That keeps prompts containing quotes, backticks or $ safe
        // from breaking the shell. stdin is closed and stderr folded into
        // stdout so stray output can't corrupt the JSON stream.

        if (root.sessionId === "") {
            proc.command = ["sh", "-c", 'exec "$0" run --format json "$1" < /dev/null 2>&1', opencodeBin, t];
        } else {
            proc.command = ["sh", "-c", 'exec "$0" run --format json --session "$2" "$1" < /dev/null 2>&1', opencodeBin, t, root.sessionId];
        }
        proc.running = true;
    }

    // ---------------------------------------------------------------------
    // Processes
    // ---------------------------------------------------------------------

    Process {
        id: proc
        workingDirectory: homePath
        // NO_COLOR / TERM=dumb keep opencode from emitting terminal escapes
        // into a stream we are about to JSON.parse line by line.

        environment: ({
                NO_COLOR: "1",
                TERM: "dumb"
            })

        onStarted: console.log("PROCESO INICIADO")

        // StdioCollector buffers stdout and emits onStreamFinished when the
        // stream closes. Simple, but it means no incremental output — for real
        // streaming use DataStreamParser or SplitParser from Quickshell.Io.

        stdout: StdioCollector {
            onStreamFinished: {
                console.log("OUT completo:", text);
                root.handleOutput(text);
            }
        }

        // If opencode died without producing text, the placeholder would sit
        // there spinning forever. Surface the exit code instead of leaving a
        // silent failure.

        onExited: (code, status) => {
            console.log("opencode terminó, código:", code, "status:", status);
            const i = chat.count - 1;
            if (i >= 0 && chat.get(i).role === "ai" && chat.get(i).text === "")
                chat.setProperty(i, "text", "(sin respuesta, código " + code + ")");
        }
    }

    // ---------------------------------------------------------------------
    // UI — one PanelWindow per monitor, all stacked, only one expanded.
    // ---------------------------------------------------------------------

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            screen: modelData

            // Derived from root.activeScreen. Each window knows whether it is
            // "the" open one; the rest stay collapsed showing just the eyes.

            readonly property bool open: root.activeScreen === modelData.name
            // 0 = collapsed bar, 1 = full bubble. Every dimension below is
            // interpolated from this single value, so the whole transition
            // stays in sync. The Behavior animates changes to it.

            property real progress: open ? 1 : 0

            Behavior on progress {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }

            // Opening clears the unread flag (stopping the blink) and defers
            // focus to the input via Qt.callLater, which waits a tick so the
            // window is fully mapped before the keyboard focus request lands.

            onOpenChanged: {
                if (open) {
                    root.unread = false;
                    Qt.callLater(() => inputBar.focusInput());
                }
            }

            // Layer-shell config. Top layer floats above everything.
            // exclusionMode Ignore keeps it from reserving space in the
            // compositor's panel layout. keyboardFocus is conditional: a
            // collapsed widget must never steal focus from other apps.
            // namespace identifies the surface to the compositor.

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "meowko"
            WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore

            anchors.top: true
            margins.top: 0

            implicitWidth: root.openW
            implicitHeight: root.openH
            color: "transparent"
            // Clip the input region to the visible box, so the transparent
            // parts of the 600x340 surface do not swallow clicks meant for
            // windows underneath.

            mask: Region {
                item: box
            }

            // -----------------------------------------------------------------
            // The animated box. Its size lerps between closed and open, and
            // its color carries the unread alert.
            // -----------------------------------------------------------------

            Rectangle {
                id: box
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.closedW + (root.openW - root.closedW) * win.progress
                height: root.closedH + (root.openH - root.closedH) * win.progress

                // Unread alert driver. flash runs 0 -> 1 -> 0 on a loop; every
                // color below derives from it, so background and eyes stay in
                // sync and invert together.

                property real flash: 0
                readonly property bool wantFlash: root.unread && !win.open

                // Snap back to the resting color the moment the alert stops.
                // Without this, opening the widget mid-fade would leave the
                // box stuck on a grey in-between value.

                onWantFlashChanged: if (!wantFlash)
                    flash = 0

                // Slow fade to white (2.6s), hold (1.4s), fade back (2.6s),
                // hold again — an 8s cycle. InOutSine eases in and out so it
                // breathes instead of pulsing mechanically.

                SequentialAnimation on flash {
                    running: box.wantFlash
                    loops: Animation.Infinite

                    NumberAnimation {
                        to: 1
                        duration: 2600
                        easing.type: Easing.InOutSine
                    }
                    PauseAnimation {
                        duration: 1400
                    }
                    NumberAnimation {
                        to: 0
                        duration: 2600
                        easing.type: Easing.InOutSine
                    }
                    PauseAnimation {
                        duration: 1400
                    }
                }

                // Blend cBg toward white by `flash`. Interpolating the color
                // (rather than switching it) is what makes the blink soft
                // instead of a hard strobe between black and white.

                readonly property color flashBg: Qt.rgba(root.cBg.r + (1 - root.cBg.r) * box.flash, root.cBg.g + (1 - root.cBg.g) * box.flash, root.cBg.b + (1 - root.cBg.b) * box.flash)

                color: box.flash > 0 ? box.flashBg : root.cBg
                clip: true
                radius: Math.min(24, width / 2, height / 2)

                // Rounded bottom corners only, so collapsed it reads as a tab
                // hanging from the top edge rather than a floating pill.

                topLeftRadius: 0
                topRightRadius: 0

                // Click anywhere on the collapsed bar to open it. Disabled while open.
                MouseArea {
                    anchors.fill: parent
                    enabled: !win.open
                    onClicked: root.activeScreen = win.modelData.name
                }

                // The eyes — now a component (components/Eyes.qml). Anchored
                // here; flash/progress/expanded are passed in as properties so
                // the component needs no knowledge of `box` or `win`.

                Eyes {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: root.closedH
                    flash: box.flash
                    progress: win.progress
                    expanded: win.open
                }

                // The expanded UI: header, message list, input. Sized to the
                // full open dimensions regardless of progress, and faded in
                // only over the last 40% of the animation (0.6 -> 1.0) so it
                // appears once the box has settled and the reveal is not
                // visibly rescaled.
                ColumnLayout {
                    width: root.openW
                    height: root.openH
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    opacity: Math.max(0, (win.progress - 0.6) / 0.4)
                    visible: opacity > 0

                    // -- Header -------------------------------------------------
                    // Session name + "nuevo" on the left, volume and close on
                    // the right. Interaction is surfaced as signals so the
                    // component only knows about the session state.
                    Header {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        Layout.leftMargin: 20
                        Layout.rightMargin: 20
                        sessionId: root.sessionId
                        muted: root.muted
                        textColor: root.cText
                        dimColor: root.cDim
                        fontFamily: root.fontFamily
                        onNewRequested: root.newChat()
                        onMuteRequested: root.muted = !root.muted
                        onCloseRequested: root.activeScreen = ""
                    }

                    // -- Message list ------------------------------------------
                    // The transcript. Scroll behaviour lives inside the
                    // component; `responded` asks it to jump back to your
                    // message when a fresh answer lands.
                    MessageList {
                        id: msgList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 20
                        Layout.rightMargin: 20
                        model: chat
                        bubbleColor: root.cBubble
                        textColor: root.cText
                        aiColor: root.cAi
                        dimColor: root.cDim
                        fontFamily: root.fontFamily
                    }

                    // -- Footer -------------------------------------------------
                    // Status cat + prompt input. `busy` is wired straight to
                    // the process state; sending and closing are signals.
                    InputBar {
                        id: inputBar
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.rightMargin: 14
                        Layout.bottomMargin: 14
                        busy: proc.running
                        inputColor: root.cInput
                        textColor: root.cText
                        dimColor: root.cDim
                        fontFamily: root.fontFamily
                        onSendRequested: root.send(text)
                        onCloseRequested: root.activeScreen = ""
                    }
                }
            }
        }
    }

    // The main file still owns the cross-component wiring: when a full answer
    // has been written (root.answered), tell the list to scroll your message
    // back to the top so the reply slides in underneath it.
    Connections {
        target: root
        function onAnswered() {
            msgList.responded();
        }
    }
}