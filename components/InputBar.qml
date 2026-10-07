import QtQuick
import QtQuick.Layouts

// Bottom bar: the status cat, the prompt field and its placeholder, a ■ stop
// button (only while a request runs) plus two floating overlays — the
// /comandos suggestions popup and the "Esc de nuevo para cancelar" chip.
//
// The root is a plain Item so the overlays can anchor freely; the actual bar
// is the RowLayout below. The outer file sets Layout.* on this component,
// which apply to the Item.

Item {
    id: inputBar

    required property bool busy
    property color inputColor: "#141416"
    property color textColor: "#f2f2f2"
    property color dimColor: "#6b6b70"
    property string fontFamily: "Inter"

    // The command catalogue (a ListModel of {name, hint}) used for the popup.
    property var commands: null

    // A plain Item has zero implicit size; without this the ColumnLayout in
    // meowko collapses the whole bar (cat + input) to 0 height. The bar's own
    // implicit height plus its bottom margin is what it really occupies.
    implicitHeight: bar.implicitHeight + 14

    signal sendRequested(string text)
    signal closeRequested
    signal cancelRequested

    // Recalculated suggestions: array of the {name, hint} entries whose name
    // starts with what the user typed and is not yet exactly that.
    property var suggestions: []
    // True after Escape dismissed the popup; typing again clears it.
    property bool suppressed: false
    // First Escape with a request running armed a cancellation; the second
    // one within 1.5 s fires cancelRequested(). The chip shows that window.
    property bool cancelArmed: false

    // Disarms the two-Esc cancellation after 1.5 s.
    Timer {
        id: disarmTimer
        interval: 1500
        repeat: false
        onTriggered: inputBar.cancelArmed = false
    }

    // A finished request can no longer be cancelled; drop the armed state so
    // the next Escape closes the widget like normal.
    onBusyChanged: {
        if (!busy) {
            inputBar.cancelArmed = false;
            disarmTimer.stop();
        }
    }

    // Called on expand so the field is ready to type immediately.
    function focusInput() {
        input.forceActiveFocus();
    }

    function updateSuggestions() {
        const t = input.text.trim();
        if (!t.startsWith("/") || t.includes(" ") || !inputBar.commands || typeof inputBar.commands.count === "undefined" || inputBar.commands.count === 0) {
            inputBar.suggestions = [];
            return;
        }
        const out = [];
        for (let i = 0; i < inputBar.commands.count; i++) {
            const name = inputBar.commands.get(i).name;
            const hint = inputBar.commands.get(i).hint;
            if (name.startsWith(t) && name !== t)
                out.push({
                    name: name,
                    hint: hint
                });
        }
        inputBar.suggestions = out;
    }

    // Tab: replace the text with the first suggestion plus a space.
    function complete() {
        if (inputBar.suggestions.length === 0)
            return;
        const s = inputBar.suggestions[0];
        input.text = s.name + " ";
        input.cursorPosition = input.text.length;
        inputBar.updateSuggestions();
    }

    // Click: same as Tab but for a chosen row.
    function insertSuggestion(i) {
        input.text = inputBar.suggestions[i].name + " ";
        input.cursorPosition = input.text.length;
        input.forceActiveFocus();
        inputBar.updateSuggestions();
    }

    RowLayout {
        id: bar
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.bottomMargin: 14
        spacing: 10

        // Cat.qml lives in the same folder, so no import statement is needed.
        Cat {
            Layout.alignment: Qt.AlignVCenter
            busy: inputBar.busy
            width: 26
        }

        Rectangle {
            Layout.fillWidth: true
            height: 38
            radius: 19
            color: inputBar.inputColor

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                verticalAlignment: TextInput.AlignVCenter
                font.family: inputBar.fontFamily
                font.pixelSize: 13
                color: inputBar.textColor
                selectionColor: "white"
                selectedTextColor: "black"
                clip: true

                // recompute the popup as the user types
                onTextChanged: {
                    inputBar.suppressed = false;
                    inputBar.updateSuggestions();
                }
                Keys.onTabPressed: inputBar.complete()
                Keys.onEscapePressed: {
                    if (inputBar.suggestions.length > 0 && !inputBar.suppressed) {
                        // popup is up: just dismiss it
                        inputBar.suppressed = true;
                    } else if (inputBar.busy && inputBar.cancelArmed) {
                        // second Esc within 1.5 s: cancel right away
                        inputBar.cancelArmed = false;
                        disarmTimer.stop();
                        inputBar.cancelRequested();
                    } else if (inputBar.busy) {
                        // first Esc with a request running: arm the cancellation
                        inputBar.cancelArmed = true;
                        disarmTimer.restart();
                    } else {
                        inputBar.closeRequested();
                    }
                }

                onAccepted: {
                    inputBar.cancelArmed = false;
                    disarmTimer.stop();
                    inputBar.sendRequested(text);
                    text = "";
                }

                Text {
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "pregunta algo…"
                    color: inputBar.dimColor
                    font: input.font
                }
            }
        }

        // The ■ stop button — cancels immediately, only while a request runs.
        Rectangle {
            visible: inputBar.busy
            Layout.alignment: Qt.AlignVCenter
            width: 26
            height: 26
            radius: 6
            color: inputBar.inputColor
            border.color: Qt.rgba(1, 1, 1, 0.12)

            Text {
                anchors.centerIn: parent
                text: "\u25A0"
                font.pixelSize: 11
                color: stopMouse.containsMouse ? inputBar.textColor : inputBar.dimColor
            }
            MouseArea {
                id: stopMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: inputBar.cancelRequested()
            }
        }
    }

    // -----------------------------------------------------------------
    // Chip shown while a cancellation is armed — tells you the next Esc
    // cancels, and disappears when the request finishes or the timer runs out.
    // -----------------------------------------------------------------

    Rectangle {
        visible: inputBar.cancelArmed
        z: 3
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 60
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 8
        color: inputBar.inputColor
        border.color: Qt.rgba(1, 1, 1, 0.12)
        width: chipText.implicitWidth + 20
        height: chipText.implicitHeight + 12

        Text {
            id: chipText
            anchors.centerIn: parent
            text: "Esc de nuevo para cancelar"
            font.family: inputBar.fontFamily
            font.pixelSize: 10
            color: inputBar.textColor
        }
    }

    // -----------------------------------------------------------------
    // Suggestions popup. Floats above the bar and lists the /comandos whose
    // name starts with the typed prefix.
    // -----------------------------------------------------------------

    Rectangle {
        id: popup
        z: 3
        width: 260
        height: 8 + Math.min(inputBar.suggestions.length, 8) * 24
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 60
        anchors.left: parent.left
        anchors.leftMargin: 16
        visible: inputBar.suggestions.length > 0 && !inputBar.suppressed
        radius: 10
        color: inputBar.inputColor
        border.color: Qt.rgba(1, 1, 1, 0.08)
        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 2

            Repeater {
                model: inputBar.suggestions.length

                RowLayout {
                    id: suggestion
                    required property int index
                    height: 24

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: suggMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                        MouseArea {
                            id: suggMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: inputBar.insertSuggestion(index)
                        }
                    }
                    Text {
                        Layout.leftMargin: 8
                        text: inputBar.suggestions[index].name
                        font.family: inputBar.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                        color: inputBar.textColor
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Text {
                        Layout.rightMargin: 8
                        elide: Text.ElideRight
                        text: inputBar.suggestions[index].hint
                        font.family: inputBar.fontFamily
                        font.pixelSize: 10
                        color: inputBar.dimColor
                    }
                }
            }
        }
    }
}