// created by musesum on 3/26/25

import QuartzCore
import UIKit
import MuFlo
import MuHands // Touch*

public class DrawDot {

    private var noteItems: [Int: MidiMpeItem] = [:]
    private var root˚   : Flo! /// root of tree
    private var base˚   : Flo! /// base flo on/off
    private var noteOn˚ : Flo? /// midi note on
    private var noteOff˚: Flo? /// midi note off
    private var wheel˚  : Flo? /// pitch wheel
    private var slide˚  : Flo? /// mpe slide pitch
    private var after˚  : Flo? /// aftertouch
    private var clear˚  : Flo? /// clear screen event

    private var bufSize = CGSize.zero
    private var drawBuf: UnsafeMutablePointer<UInt32>?
    private var running: Bool = false
    private var logging: Bool = false
    private var touchCanvas: TouchCanvas

    public init(_ root˚: Flo,
                _ path: String,
                _ touchCanvas: TouchCanvas) {

        self.root˚ = root˚
        self.touchCanvas = touchCanvas
        self.base˚ = root˚.bind(path)   { f,_ in self.updateBase(f) }
        noteOn˚ = base˚.bind("note.on") { f,_ in self.updateNoteOn(f) }
        noteOn˚ = base˚.bind("note.off"){ f,_ in self.updateNoteOff(f) }
        wheel˚  = base˚.bind("wheel")   { f,_ in self.updateWheel(f) }
        slide˚  = base˚.bind("slide")   { f,_ in self.updateSlide(f) }
        after˚  = base˚.bind("after")   { f,_ in self.updateAfter(f) }
        clear˚  = base˚.bind("clear")   { f,_ in self.clearCanvas() }
        base˚.activate([])
    }

    func updateNoteOn(_ flo: Flo) {
        guard running else { return }
        if let chan = flo.intVal("chan"),
           let num  = flo.intVal("num"),
           let velo = flo.intVal("velo") {
            if logging {
                TimeLog("note\(chan)", interval: 0) { P("noteOn:  \(chan), \(num), \(velo)") }
            }
            if let noteItem = noteItems[chan] {
                noteItem.update(velo: velo, phase: .began)
                drawMpeItem(noteItem)
            } else {
                let noteItem = MidiMpeItem(chan,num,velo,logging)
                noteItems[chan] = noteItem
                drawMpeItem(noteItem)
            }
        }
    }

    func updateNoteOff(_ flo: Flo) {
        guard running else { return }
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
        guard running else { return }
        if let chan = flo.intVal("chan"),
           let val  = flo.intVal("val") {
            let val = val - 8192
            if logging {
                TimeLog("wheel\(chan)", interval: 0.25) { P("wheel: \(chan), \(val)") }
            }
            if let noteItem = noteItems[chan] {
                noteItem.update(wheel: val, phase: .moved)
                drawMpeItem(noteItem)
            }
        }
    }
    func updateSlide(_ flo: Flo) {
        guard running else { return }
        if let chan = flo.intVal("chan"),
           let val  = flo.intVal("val") {
            if logging {
                TimeLog("slide\(chan)", interval: 0.25) { P("slide: \(chan), \(val) \(val)") }
            }
            if let noteItem = noteItems[chan] {
                noteItem.update(slide: val, phase: .moved)
                drawMpeItem(noteItem)
            }
        }
    }
    func updateAfter(_ flo: Flo) {
        guard running else { return }
        if let chan = flo.intVal("chan"),
           let val = flo.intVal("val") {
            if logging {
                TimeLog("after\(chan)", interval: 0.25) { P("after: \(chan), \(val)") }
            }
            if let noteItem = noteItems[chan] {
                noteItem.update(after: val, phase: .moved)
                drawMpeItem(noteItem)
            }
        }
    }
    func updateBase(_ flo: Flo) {
        running = flo.boolVal("on")
        logging = flo.boolVal("log")
    }
    func clearCanvas() {
        guard running else { return }
        if logging {
            TimeLog("dot clear ", interval: 0) { P("dot clear all") }
        }
        for (chan, item) in noteItems {
            noteItems[chan] = nil
            item.update(velo: 0, phase: .ended)
            drawMpeItem(item)
        }
        noteItems.removeAll()
    }
    func drawMpeItem(_ item: MidiMpeItem) {
        let scale = touchCanvas.scale
        let size = touchCanvas.drawableSize / scale
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
        touchCanvas.remoteItem(item)
    }
}
