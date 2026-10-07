import QtQuick

// System notice row: grey plain text for the output of /comandos (e.g.
// /help, /mute). Never hinted as an AI or user message.

Text {
    id: sysMsg

    required property string text
    property string fontFamily: "Inter"

    width: parent.width
    text: sysMsg.text
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: "#6b6b70"
    font.family: sysMsg.fontFamily
    font.pixelSize: 11
    topPadding: 1
    bottomPadding: 1
}