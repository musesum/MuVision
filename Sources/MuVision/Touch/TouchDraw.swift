
import QuartzCore
import UIKit
import MuFlo


public class NoteItem {

    var chan: Int // channel for MPE note events
    var note: Int // note number, not changed for MPE
    var velo: Int // velocity
    var lift: Int = 0 // speed of lifting finger for NoteOff
    var wheel: Int = 0
    var slide: Int = 0
    var after: Int = 0
    var phase: UITouch.Phase = .began

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
         _ velo: Int) {

        self.chan = chan
        self.note = note
        self.velo = velo
        self.after = velo
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

public class MidiDraw {
    public static var shared = MidiDraw()

    var noteItems: [Int: NoteItem] = [:]

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

    public func parseRoot(_ root: Flo,
                          _ archiveFlo: ArchiveFlo) {
        self.root = root
        self.archiveFlo = archiveFlo
        let dot = root .bind("sky.draw.dot")
        dotNoteOn˚ = dot.bind("note.on") { f,_ in self.updateNoteOn(f) }
        dotNoteOn˚ = dot.bind("note.off"){ f,_ in self.updateNoteOff(f) }
        dotWheel˚  = dot.bind("wheel")   { f,_ in self.updateWheel(f) }
        dotSlide˚  = dot.bind("slide")   { f,_ in self.updateSlide(f) }
        dotAfter˚  = dot.bind("after")   { f,_ in self.updateAfter(f) }
        dotClear˚  = dot.bind("clear")   { f,_ in self.clearCanvas() }
    }

    func updateNoteOn(_ flo: Flo) {
        if let chan = flo.intVal("chan"),
           let num  = flo.intVal("num"),
           let velo = flo.intVal("velo") {
            NoTimeLog("note\(chan)", interval: 0) { P("noteOn:  \(chan), \(num), \(velo)") }
            if let noteItem = noteItems[chan] {
                noteItem.update(velo: velo, phase: .began)
                drawNoteItem(noteItem)
            } else {
                let noteItem = NoteItem(chan,num,velo)
                noteItems[chan] = noteItem
                drawNoteItem(noteItem)
            }
        }
    }

    func updateNoteOff(_ flo: Flo) {
        if let chan = flo.intVal("chan"),
           let velo = flo.intVal("velo") {
            NoTimeLog("note\(chan)", interval: 0) { P("noteOff: \(chan), \(velo)") }
            if let noteItem = noteItems[chan] {
                noteItem.update(lift: velo, phase: .ended)
                drawNoteItem(noteItem)
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
                drawNoteItem(noteItem)
            }
        }
    }
    func updateSlide(_ flo: Flo) {
        if let chan = flo.intVal("chan"),
           let val  = flo.intVal("val") {
            NoTimeLog("slide\(chan)", interval: 0.25) { P("slide: \(chan), \(val) \(val)") }
            if let noteItem = noteItems[chan] {
                noteItem.update(slide: val, phase: .moved)
                drawNoteItem(noteItem)
            }
        }
    }
    func updateAfter(_ flo: Flo) {
        if let chan = flo.intVal("chan"),
           let val = flo.intVal("val") {
            NoTimeLog("_after\(chan)", interval: 0.25) { P("after: \(chan), \(val)") }
            if let noteItem = noteItems[chan] {
                noteItem.update(after: val, phase: .moved)
                drawNoteItem(noteItem)
            }
        }
    }
    func clearCanvas() {
        NoTimeLog("dot clear ", interval: 0) { P("dot clear all") }
        for (chan,item) in noteItems {
            noteItems[chan] = nil
            item.update(velo: 0, phase: .ended)
            drawNoteItem(item)
        }
        noteItems.removeAll()
    }
    func drawNoteItem(_ item: NoteItem) {
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

        let key = "midi\(item.chan)".hash
        let item = TouchCanvasItem(key, point, radius, .zero, .zero, item.phase, Visitor(0, .midi))
        TouchCanvas.shared.remoteItem(item)
    }
}


public class TouchDraw {

    public static var shared = TouchDraw()

    private var root     : Flo?
    private var tilt˚    : Flo? ; var tilt    = false
    private var press˚   : Flo? ; var press   = true
    private var size˚    : Flo? ; var size    = CGFloat(1)
    private var index˚   : Flo? ; var index   = UInt32(255)
    private var prev˚    : Flo? ; var prev    = CGPoint.zero
    private var next˚    : Flo? ; var next    = CGPoint.zero
    private var force˚   : Flo? ; var force   = CGFloat(0)
    private var radius˚  : Flo? ; var radius  = CGFloat(0)
    private var azimuth˚ : Flo? ; var azimuth = CGPoint.zero
    private var fill˚    : Flo? ; var fill    = Float(-1)

    private var bufSize = CGSize.zero
    private var drawBuf: UnsafeMutablePointer<UInt32>?
    private var archiveFlo: ArchiveFlo?
    public var drawableSize = CGSize.zero
    public var drawUpdate: MTLTexture?

    public func parseRoot(_ root: Flo,
                          _ archiveFlo: ArchiveFlo) {

        self.root = root
        self.archiveFlo = archiveFlo

        MidiDraw.shared.parseRoot(root, archiveFlo)

        let sky    = root.bind("sky"   )
        let input  = sky .bind("input" )
        let draw   = sky .bind("draw"  )
        let brush  = draw.bind("brush" )
        let line   = draw.bind("line"  )
        let screen = draw.bind("screen")

        tilt˚    = input .bind("tilt"   ){ f,_ in self.tilt    = f.bool    }
        press˚   = brush .bind("press"  ){ f,_ in self.press   = f.bool    }
        size˚    = brush .bind("size"   ){ f,_ in self.size    = f.cgFloat }
        index˚   = brush .bind("index"  ){ f,_ in self.index   = f.uint32  }
        prev˚    = line  .bind("prev"   ){ f,_ in self.prev    = f.cgPoint }
        next˚    = line  .bind("next"   ){ f,_ in self.next    = f.cgPoint }
        force˚   = input .bind("force"  ){ f,_ in self.force   = f.cgFloat }
        radius˚  = input .bind("radius" ){ f,_ in self.radius  = f.cgFloat }
        azimuth˚ = input .bind("azimuth"){ f,_ in self.azimuth = f.cgPoint }
        fill˚    = screen.bind("fill"   ){ f,_ in self.fill    = f.float   }
    }
}
extension TouchDraw {
    /// get radius of TouchCanvasItem
    public func updateRadius(_ item: TouchCanvasItem) -> CGFloat {

        let visit = item.visit()

        // if using Apple Pencil and brush tilt is turned on
        if item.force > 0, tilt {
            let azi = CGPoint(x: CGFloat(-item.azimY), y: CGFloat(-item.azimX))
            azimuth˚?.setAnyExprs(azi, .fire, visit)
            //PrintGesture("azimuth dXY(%.2f,%.2f)", item.azimuth.dx, item.azimuth.dy)
        }

        // if brush press is turned on
        var radiusNow = CGFloat(1)
        if press {
            if force > 0 || item.azimX != 0.0 {
                force˚?.setAnyExprs(item.force, .fire, visit) // will update local azimuth via FloGraph
                radiusNow = size
            } else {
                radius˚?.setAnyExprs(item.radius, .fire, visit)
                radiusNow = radius
            }
        } else {
            radiusNow = size
        }
        return radiusNow
    }
    @inline(__always)
    public func drawPoint(_ point: CGPoint,
                          _ radius: CGFloat) {

        guard let drawBuf else { return }
        if point == .zero { return }

        #if os(visionOS)
        let scale = CGFloat(3)
        #else
        let scale = UIScreen.main.scale
        #endif

        let viewPoint = point * scale
        let texPoint = touchViewToTex(viewPoint, drawableSize, bufSize)

        let r = radius * 2.0 - 1
        let r2 = Int(r * r / 4.0)
        let texW = Int(bufSize.width)
        let texH = Int(bufSize.height)
        let texMax = Int(bufSize.width * bufSize.height)
        let texX = Int(texPoint.x)
        let texY = Int(texPoint.y)

        var x0 = Int(texPoint.x - radius - 0.5)
        var y0 = Int(texPoint.y - radius - 0.5)
        var x1 = Int(texPoint.x + radius + 0.5)
        var y1 = Int(texPoint.y + radius + 0.5)

        while x0 < 0 { x0 += texW }
        while y0 < 0 { y0 += texH }
        while x1 < x0 { x1 += texW }
        while y1 < y0 { y1 += texH }

        if radius == 1 {
            drawBuf[y0 * texW + x0] = index
            return
        }

        for y in y0 ..< y1 {

            for x in x0 ..< x1  {

                let xd = (x - texX) * (x - texX)
                let yd = (y - texY) * (y - texY)

                if xd + yd < r2 {

                    let yy = (y + texH) % texH  // wrapped pixel y index
                    let xx = (x + texW) % texW  // wrapped pixel x index
                    let ii = (yy * texW + xx) % texMax // final pixel x, y index into buffer

                    drawBuf[ii] = index     // set the buffer to value
                }
            }
        }
    }
    @inline(__always)
    public func touchViewToTex(_ touch: CGPoint,
                               _ drawableSize: CGSize,
                               _ texSize: CGSize) -> CGPoint {

        let clipFill = fillClip(in: texSize, out: drawableSize)
        let clipNorm = clipFill.normalize()

        let clipX_ = clipNorm.minX
        let clipY_ = clipNorm.minY
        let clipW_ = clipNorm.width
        let clipH_ = clipNorm.height

        let touchX_ = touch.x / drawableSize.width
        let touchY_ = touch.y / drawableSize.height

        let texW = texSize.width
        let texH = texSize.height

        let xTex = (touchX_ * clipW_ + clipX_) * texW
        let yTex = (touchY_ * clipH_ + clipY_) * texH

        let result = CGPoint(x: xTex, y: yTex)

        return result
    }
}
extension TouchDraw {
    
    @inline(__always)
    public func drawIntoBuffer(_ drawBuf: UnsafeMutablePointer<UInt32>,
                               _ drawSize: CGSize) {

        self.drawBuf = drawBuf
        self.bufSize = drawSize

        let drawWidth  : Int
        let drawHeight : Int
        switch drawSize.aspect {
        case .landscape:
            drawWidth  = Int(drawSize.width)
            drawHeight = Int(drawSize.height)
        default:
            drawWidth  = Int(drawSize.height)
            drawHeight = Int(drawSize.width)
        }
        let drawCount = drawWidth * drawHeight // count

        if updateDraw() {
            // fill with mtl texture
        } else if fill > 255 {
            drawFill(UInt32(fill))
        } else if fill >= 0 {
            let v8 = UInt32(fill * 255)
            let fill = (v8 << 24) + (v8 << 16) + (v8 << 8) + v8
            drawFill(fill)
        }
        self.fill = -1

        // fill with mtl texture
        func updateDraw() -> Bool {
            guard let drawUpdate,
                  let updateData = drawUpdate.rawData() else { return false }

            let updateWidth  : Int
            let updateHeight : Int
            switch drawUpdate.aspect {
            case .landscape:
                updateWidth  = Int(drawUpdate.width)
                updateHeight = Int(drawUpdate.height)
            default:
                updateWidth  = Int(drawUpdate.height)
                updateHeight = Int(drawUpdate.width)
            }

            let clipWidth = min(drawWidth, updateWidth)
            let clipHeight = min(drawHeight, updateHeight)

            updateData.withUnsafeBytes { updatePtr in
                let update32Ptr = updatePtr.bindMemory(to: UInt32.self)
                for y in 0 ..< clipHeight {
                    for x in 0 ..< clipWidth {
                        let ui = y * updateWidth + x
                        let di = y * drawWidth + x
                        drawBuf[di] = update32Ptr[ui]
                    }
                }
            }
            DebugLog { P("📋 updateDraw bufSize\(drawSize.digits(0))") }
            self.drawUpdate = nil
            return true
        }
        func drawFill(_ fill: UInt32) {
            for i in 0 ..< drawCount {
                drawBuf[i] = fill
            }
        }
    }
}
