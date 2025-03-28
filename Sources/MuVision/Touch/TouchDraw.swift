
import QuartzCore
import MuFlo

public class TouchDraw {

    public static var shared = TouchDraw()

    var root     : Flo?
    var tilt˚    : Flo? ; var tilt    = false
    var press˚   : Flo? ; var press   = true
    var size˚    : Flo? ; var size    = CGFloat(1)
    var index˚   : Flo? ; var index   = UInt32(255)
    var prev˚    : Flo? ; var prev    = CGPoint.zero
    var next˚    : Flo? ; var next    = CGPoint.zero
    var force˚   : Flo? ; var force   = CGFloat(0)
    var radius˚  : Flo? ; var radius  = CGFloat(0)
    var azimuth˚ : Flo? ; var azimuth = CGPoint.zero
    var fill˚    : Flo? ; var fill    = Float(-1)
    
    var bufSize = CGSize.zero
    var drawBuf: UnsafeMutablePointer<UInt32>?
    var archiveFlo: ArchiveFlo?
    var drawDot: MidiDrawDot?
    var drawRipple: MidiDrawRipple?

    public var drawProto: TouchDrawProtocol? = TouchDrawDot()
    public var drawableSize = CGSize.zero
    public var drawTex: MTLTexture?

    public func parseRoot(_ root: Flo,
                          _ archiveFlo: ArchiveFlo) {

        self.root = root
        self.archiveFlo = archiveFlo
        self.drawDot = MidiDrawDot(root, archiveFlo, "sky.draw.dot" )
        self.drawRipple = MidiDrawRipple(root, archiveFlo, "sky.draw.ripple")

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
