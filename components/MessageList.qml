import QtQuick
// The message log: a ListView whose rows are one of three component states —
// user bubble, ai answer or thinking dots — selected by the role/text of each
// model row.

ListView {
    id: list

    // Model is the ListView's own built-in property, assigned at the usage
    // site (meowko.qml) as `model: chat`.
    property color bubbleColor: "#1c1c1e"
    property color textColor: "#f2f2f2"
    property color aiColor: "#d0d0d0"
    property color dimColor: "#6b6b70"
    property string fontFamily: "Inter"

    // Raised by meowko.qml when a new answer lands, telling us to scroll the
    // pending message (last real row before it) into view.
    signal responded

    clip: true
    spacing: 12

    // Auto-scroll on changes.
    onCountChanged: positionViewAtEnd()

    onResponded: positionViewAtIndex(Math.max(0, list.count - 2), ListView.Beginning)

    delegate: Item {
        id: row
        width: ListView.view.width
        // Row height depends on the state:
        //   user         -> the bubble's own height
        //   ai placeholder -> a fixed 14px line for the thinking dots
        //   ai answer    -> text height plus 24px below for the copy button
        height: model.role === "user" ? userBubble.height : (model.text === "" ? 14 : aiMessage.bodyHeight + 24)

        UserBubble {
            id: userBubble
            visible: model.role === "user"
            anchors.right: parent.right
            text: model.text
            maxTextWidth: row.width * 0.82
            bubbleColor: list.bubbleColor
            textColor: list.textColor
            fontFamily: list.fontFamily
        }

        AiMessage {
            id: aiMessage
            visible: model.role === "ai" && model.text !== ""
            width: parent.width
            text: model.text
            textColor: list.aiColor
            actionColor: list.dimColor
            fontFamily: list.fontFamily
        }

        ThinkingDots {
            visible: model.role === "ai" && model.text === ""
            anchors.verticalCenter: parent.verticalCenter
            color: list.dimColor
        }
    }
}