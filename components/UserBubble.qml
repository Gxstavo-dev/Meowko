import QtQuick

// User message: a rounded bubble on the right.

Rectangle {
    id: bubble

    required property string text
    // Cap width for wrapping, relative to the available row width.
    property real maxTextWidth: 480
    property color bubbleColor: "#1c1c1e"
    property color textColor: "#f2f2f2"
    property string fontFamily: "Inter"

    radius: 14
    color: bubbleColor

    width: inner.width + 24
    height: inner.height + 16

    Text {
        id: inner
        x: 12
        y: 8
        // Cap the bubble at maxTextWidth so long messages wrap instead of
        // spanning the window.
        width: Math.min(implicitWidth, bubble.maxTextWidth)
        text: bubble.text
        wrapMode: Text.Wrap
        color: bubble.textColor
        font.family: bubble.fontFamily
        font.pixelSize: 13
    }
}