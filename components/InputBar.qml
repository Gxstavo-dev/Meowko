import QtQuick
import QtQuick.Layouts

// Bottom bar: the status cat plus the input field and its placeholder.

RowLayout {
    id: inputBar

    required property bool busy
    property color inputColor: "#141416"
    property color textColor: "#f2f2f2"
    property color dimColor: "#6b6b70"
    property string fontFamily: "Inter"

    signal sendRequested(string text)
    signal closeRequested

    // Called on expand so the field is ready to type immediately.
    function focusInput() {
        input.forceActiveFocus();
    }

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

            onAccepted: {
                inputBar.sendRequested(text);
                text = "";
            }
            Keys.onEscapePressed: inputBar.closeRequested()

            Text {
                // The input field anchors over the rectangle, so the placeholder
                // has to live inside it.
                visible: input.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: "pregunta algo…"
                color: inputBar.dimColor
                font: input.font
            }
        }
    }
}