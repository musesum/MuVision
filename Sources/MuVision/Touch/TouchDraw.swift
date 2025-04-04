
import QuartzCore
import MuFlo

@MainActor //_____
public class TouchDraw {

    var root     : Flo?
    var tilt˚    : Flo?
    var press˚   : Flo?
    var size˚    : Flo?
    var index˚   : Flo?
    var prev˚    : Flo?
    var next˚    : Flo?
    var force˚   : Flo?
    var radius˚  : Flo?
    var azimuth˚ : Flo?
    var fill˚    : Flo?

    public private(set) var tilt    = false
    public private(set) var press   = true
    public private(set) var size    = CGFloat(1)
    public private(set) var brush   = UInt32(255)
    public private(set) var prev    = CGPoint.zero
    public private(set) var next    = CGPoint.zero
    public private(set) var force   = CGFloat(0)
    public private(set) var radius  = CGFloat(0)
    public private(set) var azimuth = CGPoint.zero
    //.... public private(set)
    var fill    = Float(-1)

    let scale: CGFloat
    var bufSize = CGSize.zero
    var drawBuf: UnsafeMutablePointer<UInt32>?

//....    var drawDot: MidiDrawDot?
//....    var drawRipple: MidiDrawRipple?
//....    var touchCanvas: TouchCanvas?

    public var drawProto: TouchDrawProtocol? = TouchDrawDot()
    public var drawableSize = CGSize.zero
    public var drawTex: MTLTexture?

    public init(_ root: Flo,
         _ archiveFlo: ArchiveFlo,
         _ scale: CGFloat) {

        //.... self.archiveFlo = archiveFlo
        self.scale = scale
        //.... self.touchCanvas = touchCanvas
        //.... self.drawDot = MidiDrawDot(root, touchCanvas, self, archiveFlo, "sky.draw.dot" ) //.... self? refactor!
        //.... self.drawRipple = MidiDrawRipple(root, touchCanvas, self, archiveFlo, "sky.draw.ripple")

        let sky    = root.bind("sky"   )
        let input  = sky .bind("input" )
        let draw   = sky .bind("draw"  )
        let brush  = draw.bind("brush" )
        let line   = draw.bind("line"  )
        let screen = draw.bind("screen")

        tilt˚    = input .bind("tilt"   ){ f,_ in self.tilt    = f.bool    }
        press˚   = brush .bind("press"  ){ f,_ in self.press   = f.bool    }
        size˚    = brush .bind("size"   ){ f,_ in self.size    = f.cgFloat }
        index˚   = brush .bind("index"  ){ f,_ in self.brush   = f.uint32  }
        prev˚    = line  .bind("prev"   ){ f,_ in self.prev    = f.cgPoint }
        next˚    = line  .bind("next"   ){ f,_ in self.next    = f.cgPoint }
        force˚   = input .bind("force"  ){ f,_ in self.force   = f.cgFloat }
        radius˚  = input .bind("radius" ){ f,_ in self.radius  = f.cgFloat }
        azimuth˚ = input .bind("azimuth"){ f,_ in self.azimuth = f.cgPoint }
        fill˚    = screen.bind("fill"   ){ f,_ in self.fill    = f.float   }
    }
}
