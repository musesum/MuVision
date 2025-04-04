// created by musesum on 3/27/25

import Foundation
import MuFlo

public typealias Rgbs = [Rgb]

public class RippleItem {

    let palSize = 256
    var span: Int = 128
    var channel: Int = 0 // corresponds to MIDI MPE assigned channel
    var note: Int = 0 // corresponds to MIDI note number
    var startTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var logging: Bool = false

    var hsv: Hsv = Hsv(0, 1, 1)
    var rgbs: Rgbs?

    init(_ channel: Int,
         _ duration: TimeInterval = 1,
         _ hsv: Hsv,
         _ logging: Bool) {

        self.startTime = Date().timeIntervalSince1970
        self.duration = duration
        self.hsv = hsv
        self.logging = logging
        let rgb = hsv.rgb()
        let blank = Rgb(r: 0, g: 0, b: 0, a: 0)
        self.rgbs = Rgb.makeRamp(span, blank, rgb, blank, logging)
    }

    func update(_ pal: inout Rgbs) -> Bool {
        guard let rgbs else { return false }
        let timeNow = Date().timeIntervalSince1970
        let deltaTime = timeNow - startTime
        if deltaTime >= duration {
            return false
        }
        let progress = deltaTime / duration

        // Unit animation sequence with span/palSize
        //   0…127: enters onto palatte
        // 128…255: travels accross palette
        // 256…383: exits from palette
        let distance = Double(palSize + 2 * span)
        let travelled = progress * distance
        let offset = Int(travelled.rounded()) - span

        var script = logging ? "rgbs[\(channel)] \(deltaTime.digits(2))/\(duration.digits(2)) ⟹ \n" : ""
        for i in 1 ..< rgbs.count {

            let index = i + offset
            if index < 0 || index > 255 { continue }
            if logging {
                script += "\(index)\(pal[index].script()) "
            }
            if index >= 0 && index < palSize {

                pal[index] << rgbs[i]
                if logging {
                    script += "<< \(i)\(rgbs[i].script()) "
                    script += "=> \(index)\(pal[index].script())\n"
                }
            }
        }
        if logging {
            TimeLog("rgbs", interval: 0.10) { P(script) }
        }
        return true
    }
}

public class Ripples {

    nonisolated(unsafe) static var shared: Ripples = Ripples()

    let palSize = 256
    var items: [Int: RippleItem] = [:]

    func update(_ pal: inout Rgbs) {
        for (channel, item) in items {
            if item.update(&pal) == false {
                items.removeValue(forKey: channel)
                if item.logging { print("[\(channel)]$" )
                }
            }
        }
    }
    func drawMidiMpe(_ mpeItem: MidiMpeItem) {

        let note = Float(mpeItem.note)
        let bent = note + Float(mpeItem.wheel) / 8192 * 12
        let hue = fmod(Float(bent), 12) / 12 // bent note changes hue
        let hsv = Hsv(hue, 1, 1)
        let channel = mpeItem.channel
        let duration = (1 - (TimeInterval(mpeItem.velo+1) / 128)) * 4
        let key = channel * 1000 + Int(note)
        let logging = mpeItem.logging

        if let item = items[key] {
            item.duration = duration
            item.hsv = hsv
        } else {
            let item = RippleItem(key, duration, hsv, logging)
            items[key] = item
        }
    }
}
