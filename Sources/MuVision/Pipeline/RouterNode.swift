// created by musesum on 9/10/26

import Metal
import MuFlo

/// composites the routed sources (drawn real color, camera, album strip) over its
/// input, split front/back by each source's subject mask, bottom route first.
/// `feed` (before cell) passes the cell routes into the automata input;
/// `router` (after color) passes the real color routes over the false color;
/// the SD-Turbo state (2) routes nowhere until DeepMuse has SD-Turbo.
/// Route state lives in `pipe.router.<source>.{front,back,fade}`, front = path a, back = path b:
/// front/back x = output (0 empty, 1 raw, 2 SD-Turbo, 3 cell), y = z order 1…6,
/// z = that path's opacity 0…1 (the layers leaf slider), applied in whichever pass
/// draws it; fade x = the source master (canvas.mix for the camera).
/// draw's back lane is the false canvas, shown by the router pass at x 1 or 3.
public class RouterNode: ComputeNode {

    struct SourceUniform {
        var route = SIMD4<Float>(0, 6, 0, 3)   // front filter, front z order, back filter, back z order
        var fade  = SIMD4<Float>(1, 0, 0, 1)   // front fade, has mask, has texture, back fade
    }
    struct Uniforms {
        var pass = SIMD4<Float>(1, 0, 0, 0)    // x = filter this pass composites; y camera, z album: 1 = joined
        var draw = SourceUniform()
        var camera = SourceUniform()
        var album = SourceUniform()
        var luma = SIMD4<Float>(1, 1, 0, 0)   // false disk mix: real level, false level, black key, 0 off 1 real on top 2 false on top
        var curve = RouterNode.curveUniform(.identity) // the mix key's cut edge: x its half width
    }
    final class Source {
        var tex˚, mask˚, front˚, back˚, fade˚: Flo?
        var node˚: Flo?   // pipe node whose `on` gates the source; nil = always on
        let name: String
        private var lastHas = SIMD2<Float>(-1, -1) // mask, tex: log transitions only
        private(set) var lane = SIMD2<Float>(1, 1)  // the Layers opacity sliders, front and back
        private(set) var master: Float = 1          // the source master, scales both lanes
        init(_ base: Flo?, _ name: String, mask: Bool, node: Flo? = nil) {
            self.name = name
            node˚ = node
            guard let base else { return }
            tex˚   = base.superBindPath("\(name).tex")
            mask˚  = mask ? base.superBindPath("\(name).mask") : nil
            front˚ = base.findPath("\(name).front")
            back˚  = base.findPath("\(name).back")
            fade˚  = base.findPath("\(name).fade")
        }
        /// this source as the route log reads it, `u` from `uniform()` this frame
        func routeSource(_ code: String, _ u: SourceUniform) -> RouteSource {
            RouteSource(code: code, route: u.route, lane: lane, master: master)
        }
        func uniform() -> SourceUniform {
            var u = SourceUniform()
            u.route = SIMD4(Float(front˚?.val("x") ?? 0), Float(front˚?.val("y") ?? 6),
                            Float(back˚?.val("x") ?? 0),  Float(back˚?.val("y") ?? 3))
            let on = (node˚?.val("on") ?? 1) > 0   // a stopped camera or strip keeps its last texture
            lane = SIMD2(Float(front˚?.val("z") ?? 1), Float(back˚?.val("z") ?? 1))
            master = Float(fade˚?.val("x") ?? 1) // the source master scales both lanes
            u.fade = SIMD4(lane.x * master,
                           on && mask˚?.texture != nil ? 1 : 0,
                           on && tex˚?.texture != nil ? 1 : 0,
                           lane.y * master)
            if u.fade.y != lastHas.x || u.fade.z != lastHas.y {
                lastHas = SIMD2(u.fade.y, u.fade.z)
                let has = u.fade
                DebugLog { P("🔀 router.\(self.name) mask \(Int(has.y)) tex \(Int(has.z))") }
            }
            return u
        }
    }

    private var inTex˚   : Flo?
    private var outTex˚  : Flo?
    private let pass     : Float
    private let draw     : Source
    private let camera   : Source
    private let album    : Source
    private var lastJoined = SIMD2<Float>(-1, -1) // camera, album: log transitions only
    private var luma˚    : Flo?   // pipe.router.draw.luma <> canvas.luma: the false disk mix, router pass only
    private var lumaCurve˚: Flo?  // pipe.router.draw.lumaCurve <> canvas.lumaCurve: the key's depth and breadth
    private var lastStack = SIMD2<Float>(-1, -1) // mix order, key end: log transitions only
    private var routeLog = RouteLog()             // the route as the frames read it, one line a change

    /// one source as the Layers leaf shows it: its row's code, its route
    /// (front filter, front z, back filter, back z), its two opacity sliders,
    /// and the master fade the kernel multiplies both by (canvas.mix fade for
    /// the camera) -- kept apart so the log's opacity is the slider's own
    struct RouteSource: Equatable {
        var code: String
        var route: SIMD4<Float>
        var lane: SIMD2<Float>
        var master: Float = 1
    }
    /// the route in the Layers leaf's compact notation, the row order top first,
    /// each opacity slider, and any master fade that isn't 1:
    /// `DF1B0,CF3B0,AF1B1 · order A,C,D · opacity DF 0.00 DB 1.00 … · fade C 0.50`
    static func routeLine(_ sources: [RouteSource]) -> String {
        let code = sources.map { "\($0.code)F\(Int($0.route.x))B\(Int($0.route.z))" }.joined(separator: ",")
        let opacities = sources.map {
            "\($0.code)F \(digits($0.lane.x)) \($0.code)B \(digits($0.lane.y))"
        }.joined(separator: " ")
        let fades = sources.filter { digits($0.master) != digits(1) }
            .map { "\($0.code) \(digits($0.master))" }.joined(separator: " ")
        let line = "\(code) · order \(order(sources)) · opacity \(opacities)"
        return fades.isEmpty ? line : "\(line) · fade \(fades)"
    }
    /// one field per control, named as the Layers leaf's own log names it:
    /// a radio `CF 3`, the rows `order C,A,D`, a slider `CB opacity 0.40`,
    /// and a source's master `C fade 1.00`
    struct RouteField: Equatable {
        let key: String
        let value: String
    }
    static func routeFields(_ sources: [RouteSource]) -> [RouteField] {
        var fields = [RouteField]()
        for s in sources {
            fields.append(RouteField(key: "\(s.code)F", value: "\(Int(s.route.x))"))
            fields.append(RouteField(key: "\(s.code)B", value: "\(Int(s.route.z))"))
        }
        fields.append(RouteField(key: "order", value: order(sources)))
        for s in sources {
            fields.append(RouteField(key: "\(s.code)F opacity", value: digits(s.lane.x)))
            fields.append(RouteField(key: "\(s.code)B opacity", value: digits(s.lane.y)))
        }
        for s in sources {
            fields.append(RouteField(key: "\(s.code) fade", value: digits(s.master)))
        }
        return fields
    }
    /// what moved between two routes, in field order: `CF 0→3, AB opacity 1.00→0.40`;
    /// empty for the first route, which has nothing to change from
    static func routeChange(_ was: [RouteField], _ now: [RouteField]) -> String {
        let old = Dictionary(was.map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
        return now.compactMap { f in
            guard let o = old[f.key], o != f.value else { return nil }
            return "\(f.key) \(o)→\(f.value)"
        }.joined(separator: ", ")
    }
    /// the rows top first, as LeafRouterVm.setRows logs them: a row sits at
    /// its lower z and the kernel draws z 1…6, so the highest is on top
    private static func order(_ sources: [RouteSource]) -> String {
        sources.sorted { min($0.route.y, $0.route.w) > min($1.route.y, $1.route.w) }
            .map(\.code).joined(separator: ",")
    }
    private static func digits(_ f: Float) -> String { String(format: "%.2f", f) }

    /// a route is logged once it has held for `settle` frames, whoever set it
    /// -- the Layers leaf, a peer, an archive, a script -- so a slider drag
    /// is one line, not one a frame; the line leads with what changed since
    /// the last line, then the whole route
    struct RouteLog {
        static let settle = 12
        private(set) var logged = [RouteField]()
        private var pending = [RouteField]()
        private var held = 0
        mutating func frame(_ sources: [RouteSource]) -> String? {
            let fields = RouterNode.routeFields(sources)
            if fields != pending { pending = fields; held = 0 }
            held += 1
            guard held == Self.settle, pending != logged else { return nil }
            let change = RouterNode.routeChange(logged, pending)
            logged = pending
            let line = RouterNode.routeLine(sources)
            return change.isEmpty ? line : "\(change) · \(line)"
        }
    }

    /// the false disk mix as the kernel reads it: both key levels, the key end,
    /// and which whole layer is on top -- real (every real color route) or false
    static func lumaUniform(_ mix: LumaMix) -> SIMD4<Float> {
        SIMD4(mix.realLevel, mix.falseLevel, mix.black ? 1 : 0, mix.realOnTop ? 1 : 2)
    }
    /// the mix key's cut edge as the kernel reads it: its half width over luma
    static func curveUniform(_ mix: LumaMix) -> SIMD4<Float> {
        SIMD4(mix.band, 0, 0, 0)
    }
    /// the false disk point and the key's curve, script defaults where unbound
    static func lumaMix(_ luma˚: Flo, _ curve˚: Flo?) -> LumaMix {
        LumaMix(x: luma˚.val("x") ?? 1, y: luma˚.val("y") ?? 0.5,
                depth: curve˚?.val("depth") ?? LumaMix.defaultDepth,
                breadth: curve˚?.val("breadth") ?? LumaMix.defaultBreadth)
    }

    /// a masked source whose front and back both composite in this pass, with no
    /// visible route between them, is drawn once as one layer, coverage
    /// front·m + back·(1−m). Two composites let what lies beneath show through
    /// the mask's soft edge as base·m(1−m), the cell canvas's noise in the seam;
    /// joined, front 1 back 1 is the whole frame, unseparated
    static func joined(_ u: Uniforms) -> (camera: Bool, album: Bool) {
        let pass = u.pass.x
        let d = u.draw, c = u.camera, a = u.album
        func lane(_ s: SourceUniform, _ front: Bool) -> Bool {
            s.fade.z > 0.5 && (front ? s.route.x : s.route.z) == pass
        }
        // routerKernel's composites in its order: z, then draw front, false canvas,
        // camera front, back, album front, back; nil = none visible in this pass
        func slot(_ z: Float, _ order: Int, _ on: Bool) -> Int? { on ? Int(z) * 8 + order : nil }
        let slots = [slot(d.route.y, 0, d.fade.z > 0.5 && d.route.x == pass && d.fade.x > 0),
                     slot(d.route.w, 1, pass == 1 && (d.route.z == 1 || d.route.z == 3) && d.fade.w > 0),
                     slot(c.route.y, 2, lane(c, true) && c.fade.x > 0),
                     slot(c.route.w, 3, lane(c, false) && c.fade.w > 0),
                     slot(a.route.y, 4, lane(a, true) && a.fade.x > 0),
                     slot(a.route.w, 5, lane(a, false) && a.fade.w > 0)]
        func join(_ s: SourceUniform, _ front: Int, _ back: Int) -> Bool {
            guard s.fade.y > 0.5, lane(s, true), lane(s, false) else { return false }
            let f = Int(s.route.y) * 8 + front, b = Int(s.route.w) * 8 + back
            let between = min(f, b) + 1 ..< max(f, b)
            return !slots.indices.contains { i in
                i != front && i != back && slots[i].map { between.contains($0) } == true
            }
        }
        return (join(c, 2, 3), join(a, 4, 5))
    }

    override public init(_ pipeline : Pipeline,
                         _ pipeNode˚ : Flo) {

        pass = pipeNode˚.name == "feed" ? 3 : 1
        let root = pipeNode˚.getRoot()
        let router = root.findPath("pipe.router")
        draw   = Source(router, "draw", mask: false)
        camera = Source(router, "camera", mask: true, node: root.findPath("pipe.camera"))
        album  = Source(router, "album", mask: true, node: root.findPath("pipe.strip"))
        luma˚  = pass == 1 ? router?.findPath("draw.luma") : nil
        lumaCurve˚ = pass == 1 ? router?.findPath("draw.lumaCurve") : nil
        super.init(pipeline, pipeNode˚)
        inTex˚   = pipeNode˚.superBindPath("in")
        outTex˚  = pipeNode˚.superBindPath("out")
        shader   = Shader(pipeline, "pipe.router", kernel: "routerKernel")
    }

    public override func makeResources() {
        computeTexture(outTex˚)
        super.makeResources()
    }

    override public func computeShader(_ encoder: MTLComputeCommandEncoder) {
        var u = Uniforms()
        u.pass.x = pass
        u.draw = draw.uniform()
        u.camera = camera.uniform()
        u.album = album.uniform()
        #if DEBUG
        if pass == 1, let line = routeLog.frame([draw.routeSource("D", u.draw),
                                                  camera.routeSource("C", u.camera),
                                                  album.routeSource("A", u.album)]) {
            DebugLog { P("🔀 route \(line)") }
        }
        #endif
        var joinable = u
        if let luma˚ {
            let mix = RouterNode.lumaMix(luma˚, lumaCurve˚)
            u.luma = RouterNode.lumaUniform(mix)
            u.curve = RouterNode.curveUniform(mix)
            if SIMD2(u.luma.w, u.luma.z) != lastStack {
                lastStack = SIMD2(u.luma.w, u.luma.z)
                let top = lastStack.x < 1.5 ? "real over false" : "false over real"
                let key = lastStack.y > 0.5 ? "B" : "W"
                DebugLog { P("🔀 router mix \(top), key \(key)") }
            }
            // under the mix the false canvas is a layer of its own, not a route between
            joinable.draw.route.z = 0
        }
        let joined = RouterNode.joined(joinable)
        u.pass.y = joined.camera ? 1 : 0
        u.pass.z = joined.album ? 1 : 0
        if SIMD2(u.pass.y, u.pass.z) != lastJoined {
            lastJoined = SIMD2(u.pass.y, u.pass.z)
            let p = self.pass, j = lastJoined
            DebugLog { P("🔀 router pass \(Int(p)) joined camera \(Int(j.x)) album \(Int(j.y))") }
        }

        encoder.setTexture(inTex˚,       index: 0)
        encoder.setTexture(outTex˚,      index: 1)
        encoder.setTexture(draw.tex˚,    index: 2)
        encoder.setTexture(camera.tex˚,  index: 3)
        encoder.setTexture(camera.mask˚, index: 4)
        encoder.setTexture(album.tex˚,   index: 5)
        encoder.setTexture(album.mask˚,  index: 6)
        encoder.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        super.computeShader(encoder)
        outTex˚?.reactivate()
    }

    public override func logShader(_ logging: inout String,
                                   _ inOut: String) {
        let inAdr = inTex˚?.texPtr ?? ""
        let outAdr = outTex˚?.texPtr ?? ""
        let inOut = "(\(inAdr)⟶\(outAdr))"
        super.logShader(&logging, inOut)
    }
}
