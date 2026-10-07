import QtQuick
import QtQuick.Layouts

// Top bar: session name, a "+ nuevo" button, a volume toggle and a close button.

RowLayout {
    id: header

    required property string sessionId
    required property bool muted
    property string model: ""
    property string agent: ""
    property color textColor: "#f2f2f2"
    property color dimColor: "#6b6b70"
    property string fontFamily: "Inter"
    property string nerdFont: "JetBrainsMono Nerd Font"

    signal newRequested
    signal muteRequested
    signal closeRequested

    Text {
        Layout.maximumWidth: 240
        Layout.leftMargin: 12
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideMiddle
        text: header.sessionId === "" ? "sin sesión" : header.sessionId
        font.family: header.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 0.5
        color: header.dimColor
        opacity: 0.8
    }
    Text {
        id: newBtn
        Layout.leftMargin: 6
        text: "nuevo"
        font.family: header.fontFamily
        font.pixelSize: 11
        color: newMa.containsMouse ? header.textColor : header.dimColor
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
            onClicked: header.newRequested()
        }
    }
    Text {
        Layout.leftMargin: 10
        // Active model/agent, or a hint that opencode decides. elide keeps
        // long model names from pushing the buttons out.
        Layout.maximumWidth: 220
        elide: Text.ElideRight
        text: (header.model !== "" || header.agent !== "") ? [header.model, header.agent].filter(s => s !== "").join(" · ") : "modelo por defecto"
        font.family: header.fontFamily
        font.pixelSize: 10
        color: header.dimColor
        opacity: 0.8
    }
    // Push the controls to the right edge.
    Item {
        Layout.fillWidth: true
    }
    Text {
        id: volBtn
        // U+F026 muted speaker, U+F028 loud speaker.
        text: header.muted ? "\uF026" : "\uF028"
        font.family: header.nerdFont
        font.pixelSize: 14
        color: volMa.containsMouse ? header.textColor : header.dimColor
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
            onClicked: header.muteRequested()
        }
    }
    Text {
        Layout.leftMargin: 10
        text: "✕"
        font.pixelSize: 11
        color: closeMa.containsMouse ? header.textColor : header.dimColor
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
            onClicked: header.closeRequested()
        }
    }
}