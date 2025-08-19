// created by musesum on 3/26/25

import UIKit
import MuFlo
import MuHands // touch

public class DrawPal: DrawDot {

    public let ripples: Ripples

    public init(_ root˚: Flo,
                _ path: String,
                _ touchCanvas: TouchCanvas,
                _ ripples: Ripples) {
        self.ripples = ripples
        super.init(root˚, path, touchCanvas)
    }
    override func drawMpeItem(_ item: MidiMpeItem) {

        ripples.drawMidiMpe(item)
    }
}

