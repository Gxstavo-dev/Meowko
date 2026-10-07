import QtQuick
import Quickshell

// AI response: no bubble, plain text on the left rendered as Markdown, with a
// copy button underneath.

Item {
    id: aiMessage

    required property string text
    property color textColor: "#d0d0d0"
    property color actionColor: "#6b6b70"
    property string fontFamily: "Inter"
    property string nerdFont: "JetBrainsMono Nerd Font"

    // Height of the rendered text. The row height formula adds 24px below it
    // to make room for the copy button.
    readonly property real bodyHeight: aiText.height

    Text {
        id: aiText
        width: parent.width
        text: aiMessage.text
        textFormat: Text.MarkdownText
        wrapMode: Text.Wrap
        color: aiMessage.textColor
        linkColor: "white"
        lineHeight: 1.25
        font.family: aiMessage.fontFamily
        font.pixelSize: 13
    }

    Text {
        id: copyBtn
        anchors.left: parent.left
        anchors.top: aiText.bottom
        anchors.topMargin: 6

        // Local feedback state. A property rather than reassigning `text`,
        // because writing to a Text that has a binding would permanently break
        // it.

        property bool copied: false

        // U+F0C5 copy icon, swaps to U+F00C check briefly after a successful
        // copy.

        text: copied ? "\uF00C" : "\uF0C5"
        font.family: aiMessage.nerdFont
        font.pixelSize: 13
        color: copyMa.containsMouse || copied ? aiMessage.textColor : aiMessage.actionColor
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
                // clipboardText is a native writable Quickshell property, so no
                // external clipboard tool (wl-copy) is needed.
                // Note: this copies the raw markdown.

                Quickshell.clipboardText = aiMessage.text;
                copyBtn.copied = true;
                copyReset.restart();
            }
        }
        Timer {
            id: copyReset
            // How long the checkmark stays before reverting to the copy icon.

            interval: 1200
            onTriggered: copyBtn.copied = false
        }
    }
}