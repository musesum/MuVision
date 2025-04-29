// created by musesum on 3/26/25

import UIKit
import MuFlo

public class DrawPal: DrawDot {

    public let ripples: Ripples

    public init(_ root˚: Flo,
                _ path: String,
                _ touchCanvas: TouchCanvas,
                _ touchDraw: TouchDraw,
                _ archiveFlo: ArchiveFlo,
                _ ripples: Ripples) {
        self.ripples = ripples
        super.init(root˚, path, touchCanvas, touchDraw, archiveFlo)
    }
    override func drawMpeItem(_ item: MidiMpeItem) {

        ripples.drawMidiMpe(item)
    }
}

