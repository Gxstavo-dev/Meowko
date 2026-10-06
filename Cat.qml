// ============================================================================
// The status cat.
//
// Two pixel-art GIFs, swapped by a single boolean. `busy` is wired straight to
// the opencode process state in shell.qml, so there is no extra state to keep
// in sync and no polling — the image changes the instant the process starts
// or stops.
//
//   busy === false  ->  gato_dormido.gif    (145x125, 28 frames)
//   busy === true   ->  gato_tranquilo.gif  (150x140, 34 frames)
// ============================================================================

import QtQuick

Item {
    id: cat

    // True while opencode is working. Set from shell.qml via `busy: proc.running`.
    property bool busy: false

    // Width is the knob; height follows the 150:140 aspect of the "tranquilo"
    // GIF so both images fit the same box. 26px is a good default — anything
    // below ~20 makes the pixel art muddy once it is scaled down.
    width: 26
    height: Math.round(width * 140 / 150)

    // Both GIFs must sit next to this file. QML resolves `source` as a URL
    // relative to the .qml location, and a space in a filename fails silently
    // (status becomes Image.Error with nothing drawn and no console error) —
    // so keep the names underscore-separated.
    AnimatedImage {
        id: gif
        anchors.fill: parent

        // Scale down to fit rather than cropping. The two GIFs have slightly
        // different aspect ratios, so the mismatch shows as a small margin.
        fillMode: Image.PreserveAspectFit

        loops: AnimatedImage.Infinite

        // Load off the main thread so a large GIF cannot stall rendering.
        asynchronous: true

        // Keep decoded frames in memory. Both GIFs are well under 100 KB, and
        // they swap often, so re-decoding on every state change would be wasteful.
        cache: true

        // NEAREST-neighbour scaling. Without this the pixel art is interpolated
        // and looks blurry at 26px — the single most visible tweak here.
        smooth: false

        // Changing `source` restarts the animation from frame 0, which is
        // exactly the desired behaviour on a state change.
        source: cat.busy ? "gato_tranquilo.gif" : "gato_dormido.gif"
    }
}