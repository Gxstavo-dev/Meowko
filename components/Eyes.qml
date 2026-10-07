import QtQuick

// The eyes. Two 5x8 rounded rects whose height is scaled by `blink`, giving
// the impression of a squint. Only visible while collapsed: opacity fades out
// by 33% of the opening progress (see meowko.qml).

Item {
    id: eyes

    // Squint factor, 1 = open, 0.1 = closed. Driven by the SequentialAnimation.
    property real blink: 1

    // Unread-alert driver, 0..1. The eyes invert toward black as it rises so
    // they do not vanish on the white flash background.
    property real flash: 0

    // 0 = collapsed, 1 = expanded. Fades the eyes out over the first 33%.
    property real progress: 0

    // True while this window is expanded; stops the idle double-blink.
    property bool expanded: false

    width: 20
    opacity: Math.max(0, 1 - progress * 3)
    visible: opacity > 0

    // Idle blink: long pause, quick close, quick open, short pause, then a
    // second blink — a double-blink reads as more lifelike than a single one.
    // Only runs while collapsed.
    SequentialAnimation on blink {
        loops: Animation.Infinite
        running: !eyes.expanded
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

    // The eyes invert to black as `flash` rises. Without this they would be
    // white-on-white and vanish at peak flash.

    Rectangle {
        x: 2
        anchors.verticalCenter: parent.verticalCenter
        width: 5
        height: 8 * eyes.blink
        radius: 2.5
        color: eyes.flash > 0 ? Qt.rgba(1 - eyes.flash, 1 - eyes.flash, 1 - eyes.flash) : "white"
    }
    Rectangle {
        x: 13
        anchors.verticalCenter: parent.verticalCenter
        width: 5
        height: 8 * eyes.blink
        radius: 2.5
        color: eyes.flash > 0 ? Qt.rgba(1 - eyes.flash, 1 - eyes.flash, 1 - eyes.flash) : "white"
    }
}