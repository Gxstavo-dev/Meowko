import QtQuick
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// ============================================================================
// meowkow — plantilla generalizada de meowko, una widget Wayland/panel-shell
// que chatea con opencode.
//
// Este archivo es la versión portátil: NO trae ningún path hardcodeado y
// funciona para cualquier usuario. Copialo a tu config y editalo libremente:
//
//     cp meowkow.qml shell.qml
//     quickshell              # o el alias qs
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
                    Qt.callLater(() => input.forceActiveFocus());
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

                // The eyes. Two 5x8 rounded rects whose height is scaled by
                // `blink`, giving the impression of a squint. Only visible
                // while collapsed: opacity fades out by 33% of the opening
                // progress (see below).

                Item {
                    id: eyes
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 20
                    height: root.closedH
                    opacity: Math.max(0, 1 - win.progress * 3)
                    visible: opacity > 0

                    // Squint factor, 1 = open, 0.1 = closed. Driven by the
                    // SequentialAnimation below.

                    property real blink: 1

                    // Idle blink: long pause, quick close, quick open, short
                    // pause, then a second blink — a double-blink reads as
                    // more lifelike than a single one. Only runs while closed.

                    SequentialAnimation on blink {
                        loops: Animation.Infinite
                        running: !win.open
                        PauseAnimation {
                            duration: 3800
                        }
                        NumberAnimation {
                            to: 0.1
                            duration: 70
                        }
                        NumberAnimation {
                            to: 1
                            duration: 90
                        }
                        PauseAnimation {
                            duration: 400
                        }
                        NumberAnimation {
                            to: 0.1
                            duration: 70
                        }
                        NumberAnimation {
                            to: 1
                            duration: 90
                        }
                    }

                    // The eyes invert to black as `flash` rises. Without this
                    // they would be white-on-white and vanish at peak flash.

                    Rectangle {
                        x: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5
                        height: 8 * eyes.blink
                        radius: 2.5
                        color: box.flash > 0 ? Qt.rgba(1 - box.flash, 1 - box.flash, 1 - box.flash) : "white"
                    }
                    Rectangle {
                        x: 13
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5
                        height: 8 * eyes.blink
                        radius: 2.5
                        color: box.flash > 0 ? Qt.rgba(1 - box.flash, 1 - box.flash, 1 - box.flash) : "white"
                    }
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

                    // Header: session ID + "nuevo" on the left, then a
                    // fillWidth spacer pushes the volume and close icons
                    // together against the right edge.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        Layout.leftMargin: 20
                        Layout.rightMargin: 20

                        // Active session ID. maximumWidth + ElideMiddle keeps
                        // long IDs from eating the space the icons need.
                        Text {
                            Layout.maximumWidth: 240
                            Layout.leftMargin: 12
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideMiddle
                            text: root.sessionId === "" ? "sin sesión" : root.sessionId
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 0.5
                            color: root.cDim
                            opacity: 0.8
                        }
                        Text {
                            id: newBtn
                            Layout.leftMargin: 6
                            text: "nuevo"
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            color: newMa.containsMouse ? root.cText : root.cDim
                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }
                            MouseArea {
                                id: newMa
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                onClicked: root.newChat()
                            }
                        }

                        // Spacer. The header has no spacing, so this is what
                        // separates the left group from the right-hand icons.
                        Item {
                            Layout.fillWidth: true
                        }

                        Text {
                            id: volBtn
                            // Volume toggle. Glyphs are Nerd Font private-use
                            // codepoints written as \uXXXX escapes: U+F028 is
                            // volume-high, U+F026 is volume-mute. Escapes keep
                            // the file readable regardless of encoding.

                            text: root.muted ? "\uF026" : "\uF028"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            color: volMa.containsMouse ? root.cText : root.cDim
                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }
                            MouseArea {
                                id: volMa
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                onClicked: root.muted = !root.muted
                            }
                        }

                        Text {
                            Layout.leftMargin: 10
                            text: "✕"
                            font.pixelSize: 11
                            color: closeMa.containsMouse ? root.cText : root.cDim
                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }
                            MouseArea {
                                id: closeMa
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                onClicked: root.activeScreen = ""
                            }
                        }
                    }

                    // -----------------------------------------------------------------
                    // Message list
                    // -----------------------------------------------------------------
                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 20
                        Layout.rightMargin: 20
                        clip: true
                        spacing: 12
                        model: chat

                        // Right after sending, scroll down: you want to see your own message and the dots.
                        onCountChanged: positionViewAtEnd()

                        // When the answer lands, jump back so YOUR message sits
                        // at the top and the reply scrolls in beneath it.
                        Connections {
                            target: root
                            function onAnswered() {
                                list.positionViewAtIndex(Math.max(0, chat.count - 2), ListView.Beginning);
                            }
                        }

                        delegate: Item {
                            id: row
                            width: ListView.view.width
                            // Height per role: the bubble sizes itself, the
                            // empty AI row is a fixed 14px strip for the dots,
                            // and a real response gets its text height + 24 to
                            // make room for the copy button underneath.

                            height: model.role === "user" ? bubble.height : (model.text === "" ? 14 : aiText.height + 24)

                            // User message: a rounded bubble on the right.
                            Rectangle {
                                id: bubble
                                visible: model.role === "user"
                                anchors.right: parent.right
                                width: userText.width + 24
                                height: userText.height + 16
                                radius: 14
                                color: root.cBubble

                                Text {
                                    id: userText
                                    x: 12
                                    y: 8
                                    width: Math.min(implicitWidth, row.width * 0.82)
                                    // Cap the bubble at 82% of the row so long
                                    // messages wrap instead of spanning the window.
                                    text: model.role === "user" ? model.text : ""
                                    wrapMode: Text.Wrap
                                    color: root.cText
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                }
                            }

                            // AI response: no bubble, plain text on the left,
                            // rendered as Markdown.
                            Text {
                                id: aiText
                                visible: model.role === "ai" && model.text !== ""
                                width: parent.width
                                text: model.role === "ai" ? model.text : ""
                                textFormat: Text.MarkdownText
                                wrapMode: Text.Wrap
                                color: root.cAi
                                linkColor: "white"
                                lineHeight: 1.25
                                font.family: root.fontFamily
                                font.pixelSize: 13
                            }

                            // Copy the response to the clipboard.
                            Text {
                                id: copyBtn
                                visible: model.role === "ai" && model.text !== ""
                                anchors.left: parent.left
                                anchors.top: aiText.bottom
                                anchors.topMargin: 6

                                // Local feedback state. A property rather than
                                // reassigning `text`, because writing to a Text
                                // that has a binding would permanently break it.

                                property bool copied: false

                                // U+F0C5 copy icon, swaps to U+F00C check
                                // briefly after a successful copy.

                                text: copied ? "\uF00C" : "\uF0C5"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                color: copyMa.containsMouse || copied ? root.cText : root.cDim
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 120
                                    }
                                }
                                MouseArea {
                                    id: copyMa
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    onClicked: {
                                        // clipboardText is a native writable
                                        // Quickshell property, so no external
                                        // clipboard tool (wl-copy) is needed.
                                        // Note: this copies the raw markdown.

                                        Quickshell.clipboardText = model.text;
                                        copyBtn.copied = true;
                                        copyReset.restart();
                                    }
                                }
                                Timer {
                                    id: copyReset
                                    // How long the checkmark stays before
                                    // reverting to the copy icon.

                                    interval: 1200
                                    onTriggered: copyBtn.copied = false
                                }
                            }

                            // "Thinking" dots. Shown only while the AI row is
                            // the empty placeholder; setLast() replaces it
                            // with the real text when the response completes.
                            Row {
                                visible: model.role === "ai" && model.text === ""
                                spacing: 5
                                anchors.verticalCenter: parent.verticalCenter

                                Repeater {
                                    model: 3
                                    Rectangle {
                                        id: dotItem
                                        required property int index
                                        width: 5
                                        height: 5
                                        radius: 2.5
                                        color: root.cDim
                                        opacity: 0.25

                                        // Staggered pulse. The leading pause is
                                        // index * 160ms and the trailing one is
                                        // (2 - index) * 160ms, so each dot fades
                                        // in sequence and the group loops as a
                                        // travelling wave rather than three dots
                                        // blinking in unison.

                                        SequentialAnimation on opacity {
                                            loops: Animation.Infinite
                                            running: dotItem.visible
                                            PauseAnimation {
                                                duration: dotItem.index * 160
                                            }
                                            NumberAnimation {
                                                to: 1
                                                duration: 320
                                            }
                                            NumberAnimation {
                                                to: 0.25
                                                duration: 320
                                            }
                                            PauseAnimation {
                                                duration: (2 - dotItem.index) * 160
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // -----------------------------------------------------------------
                    // Footer: status cat + prompt input
                    // -----------------------------------------------------------------
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.rightMargin: 14
                        Layout.bottomMargin: 14
                        spacing: 10

                        // The status cat. `busy` is wired straight to
                        // proc.running, so it swaps between the two GIFs with
                        // no extra state to keep in sync.

                        Cat {
                            Layout.alignment: Qt.AlignVCenter
                            busy: proc.running
                            width: 26
                        }

                        // The prompt: pill-shaped (height 38, radius 19),
                        // filling the remaining width next to the cat.
                        Rectangle {
                            Layout.fillWidth: true
                            height: 38
                            radius: 19
                            color: root.cInput

                            TextInput {
                                id: input
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: root.fontFamily
                                font.pixelSize: 13
                                color: root.cText
                                selectionColor: "white"
                                selectedTextColor: "black"
                                clip: true

                                // Enter sends and clears. Escape closes the
                                // whole widget from anywhere in the field.

                                onAccepted: {
                                    root.send(text);
                                    text = "";
                                }
                                Keys.onEscapePressed: root.activeScreen = ""

                                // Placeholder. `font: input.font` copies the
                                // input's font wholesale, so it stays in sync
                                // if the input's typography changes.

                                Text {
                                    visible: input.text === ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "pregunta algo…"
                                    color: root.cDim
                                    font: input.font
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
