// created by musesum on 3/26/25
import QuartzCore
import UIKit
import MuFlo

public class MidiMpeItem {

    var channel: Int // channel for MPE note events
    var note: Int // note number, not changed for MPE
    var velo: Int // velocity
    var lift: Int = 0 // speed of lifting finger for NoteOff
    var wheel: Int = 0
    var slide: Int = 0
    var after: Int = 0
    var phase: UITouch.Phase = .began
    var logging: Bool = false

    var radius: Float {
        var r = 0
        switch phase {
        case .began: r = velo
        case .ended: r = lift > after ? lift : after
        default: r = after > 0 ? after : velo
        }
        return Float(r)
    }

    init(_ chan: Int,
         _ note: Int,
         _ velo: Int,
         _ logging: Bool) {

        self.channel = chan
        self.note = note
        self.velo = velo
        self.after = velo
        self.logging = logging
    }
    func update(note: Int? = nil,
                velo: Int? = nil,
                lift: Int? = nil,
                wheel: Int? = nil,
                slide: Int? = nil,
                after: Int? = nil,
                phase: UITouch.Phase? = nil) {

        if let note { self.note = note }
        if let velo { self.velo = velo }
        if let lift { self.lift = lift }
        if let wheel { self.wheel = wheel }
        if let slide { self.slide = slide }
        if let after { self.after = after }
        if let phase { self.phase = phase }
    }
}
