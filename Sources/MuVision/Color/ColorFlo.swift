import Foundation
import MuFlo

public class ColorFlo {

    private var xfade˚: Flo?        // cross fade flo between two current palettes
    private var xfade = Float(0)  // cross fade current value
    private var pal0˚: Flo?
    private var pal0 = "rgbK"      // Red Green Blue with blacK interstitials
    private var pal1˚: Flo?
    private var pal1 = "wKZ"       // White with blacK inter pluz zeno fractal

    private var colors = [MuColor("rgbK"), MuColor("wKZ")] // dual color palette
    private var rgbs = [Rgb]()      // rendered color palette
    private var changed = true
    private var mix: UnsafeMutablePointer<UInt32>! = nil
    private var mixSize = 0

    public init(_ root: Flo) {
        if let color = root.findPath("sky.color") {
            xfade˚ = color.bind("xfade") { flo,_ in
                let fade = flo.float
                self.xfade = fade 
                self.changed = true
            }

            pal0˚ = color.bind("pal0") { flo,_ in
                self.pal0 = flo.string
                self.colors[0] = MuColor(flo.string)
                self.changed = true
            }
            pal0˚?.activate(Visitor(0, .model))

            pal1˚ = color.bind("pal1") { flo,_ in
                self.pal1 = flo.string
                self.colors[1] = MuColor(flo.string)
                self.changed = true
            }
            pal1˚?.activate(Visitor(0, .model))
        }
        changed = true
    }
    deinit {
        mix?.deallocate()
    }

    public func getMix(_ palSize: Int) -> UnsafeMutablePointer<UInt32> {
        
        if changed || palSize != mixSize {
            changed = false
            rgbs.removeAll()
            rgbs = MuColor.fade(from: colors[0], to: colors[1], xfade)
            if mixSize != palSize {
                mixSize = palSize
                mix?.deallocate()
                mix = UnsafeMutablePointer<UInt32>.allocate(capacity: mixSize)
            }

            // convert [Rgb] to [Uint32]
            for i in 0 ..< rgbs.count {
                let rgb = rgbs[i]
                let b8 = UInt32(rgb.b * 255.0)
                let g8 = UInt32(rgb.g * 255.0) << 8
                let r8 = UInt32(rgb.r * 255.0) << 16
                let a8 = UInt32(rgb.a * 255.0) << 24
                let bgra = b8 | g8 | r8 | a8
                mix[i] = bgra
                //print(String(format:"%08X", val), terminator: " ")
            }
        }
        return mix
    }

}
