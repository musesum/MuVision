// created by musesum on 3/26/25

import UIKit
import MuFlo

public class MidiDrawRipple: MidiDrawDot, @unchecked Sendable {

    private var ripples = Ripples.shared

    override func drawMpeItem(_ item: MidiMpeItem) {

        Ripples.shared.drawMidiMpe(item)
    }
}

