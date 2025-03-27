// created by musesum on 3/26/25

import QuartzCore
import UIKit
import MuFlo

public class MidiDrawDot {

    var noteItems: [Int: MidiMpeItem] = [:]

    private var root       : Flo?
    private var dotNoteOn˚ : Flo?
    private var dotNoteOff˚: Flo?
    private var dotWheel˚  : Flo?
    private var dotSlide˚  : Flo?
    private var dotAfter˚  : Flo?
    private var dotClear˚  : Flo?

    private var bufSize = CGSize.zero
    private var drawBuf: UnsafeMutablePointer<UInt32>?
    private var archiveFlo: ArchiveFlo?
    public var drawableSize = CGSize.zero
    public var drawUpdate: MTLTexture?

    init(_ root: Flo,
         _ archiveFlo: ArchiveFlo,
         _ path: String) {
        
        self.root = root
        self.archiveFlo = archiveFlo
        let base = root.bind(path) // "sky.draw.dot", "sky.draw.ripple"
        dotNoteOn˚ = base.bind("note.on") { f,_ in self.updateNoteOn(f) }
        dotNoteOn˚ = base.bind("note.off"){ f,_ in self.updateNoteOff(f) }
        dotWheel˚  = base.bind("wheel")   { f,_ in self.updateWheel(f) }
        dotSlide˚  = base.bind("slide")   { f,_ in self.updateSlide(f) }
        dotAfter˚  = base.bind("after")   { f,_ in self.updateAfter(f) }
        dotClear˚  = base.bind("clear")   { f,_ in self.clearCanvas() }
    }

    func updateNoteOn(_ flo: Flo) {
        if let chan = flo.intVal("chan"),
           let num  = flo.intVal("num"),
           let velo = flo.intVal("velo") {
            NoTimeLog("note\(chan)", interval: 0) { P("noteOn:  \(chan), \(num), \(velo)") }
            if let noteItem = noteItems[chan] {
                noteItem.update(velo: velo, phase: .began)
                drawMpeItem(noteItem)
            } else {
                let noteItem = MidiMpeItem(chan,num,velo)
                noteItems[chan] = noteItem
                drawMpeItem(noteItem)
            }
        }
    }

    func updateNoteOff(_ flo: Flo) {
        if let chan = flo.intVal("chan"),
           let velo = flo.intVal("velo") {
            NoTimeLog("note\(chan)", interval: 0) { P("noteOff: \(chan), \(velo)") }
            if let noteItem = noteItems[chan] {
                noteItem.update(lift: velo, phase: .ended)
                drawMpeItem(noteItem)
            }
        }
    }
    func updateWheel(_ flo: Flo) {
        if let chan = flo.intVal("chan"),
           let val  = flo.intVal("val") {
            let val = val - 8192
            TimeLog("wheel\(chan)", interval: 0.25) { P("wheel: \(chan), \(val)") }
            if let noteItem = noteItems[chan] {
                noteItem.update(wheel: val, phase: .moved)
                drawMpeItem(noteItem)
            }
        }
    }
    func updateSlide(_ flo: Flo) {
        if let chan = flo.intVal("chan"),
           let val  = flo.intVal("val") {
            NoTimeLog("slide\(chan)", interval: 0.25) { P("slide: \(chan), \(val) \(val)") }
            if let noteItem = noteItems[chan] {
                noteItem.update(slide: val, phase: .moved)
                drawMpeItem(noteItem)
            }
        }
    }
    func updateAfter(_ flo: Flo) {
        if let chan = flo.intVal("chan"),
           let val = flo.intVal("val") {
            NoTimeLog("_after\(chan)", interval: 0.25) { P("after: \(chan), \(val)") }
            if let noteItem = noteItems[chan] {
                noteItem.update(after: val, phase: .moved)
                drawMpeItem(noteItem)
            }
        }
    }
    func clearCanvas() {
        NoTimeLog("dot clear ", interval: 0) { P("dot clear all") }
        for (chan, item) in noteItems {
            noteItems[chan] = nil
            item.update(velo: 0, phase: .ended)
            drawMpeItem(item)
        }
        noteItems.removeAll()
    }
    func drawMpeItem(_ item: MidiMpeItem) {
        #if os(visionOS)
        let scale = CGFloat(3)
        #else
        let scale = UIScreen.main.scale
        #endif
        let size = TouchDraw.shared.drawableSize / scale
        let margin = CGFloat(48)/scale
        let xs = size.width  - margin
        let ys = size.height - margin
        let note = CGFloat(item.note % 12)
        let bent = note + CGFloat(item.wheel) / 8192 * 12
        let octave = CGFloat(item.note / 12)
        let radius = item.radius

        let xxx = margin + CGFloat(bent * xs)/12
        let yyy = margin + CGFloat(octave * ys)/12
        let point = CGPoint(x: xxx, y: yyy)

        let key = "midi\(item.channel)".hash
        let item = TouchCanvasItem(key, point, radius, .zero, .zero, item.phase, Visitor(0, .midi))
        TouchCanvas.shared.remoteItem(item)
    }
}
