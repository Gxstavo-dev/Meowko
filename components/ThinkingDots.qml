import QtQuick

// The "thinking" indicator: three dots that pulse in sequence.

Row {
    id: dots

    property color color: "#6b6b70"

    spacing: 5

    Repeater {
        model: 3
        Rectangle {
            id: dotItem
            required property int index
            width: 5
            height: 5
            radius: 2.5
            color: dots.color
            opacity: 0.25

            // Staggered pulse: each dot starts its cycle a little late so the
            // wave reads left-to-right.

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                // Only animate while the row is actually visible.
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