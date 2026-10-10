// created by musesum on 9/10/26

import Metal
import MuFlo

/// composites the routed sources (drawn real color, camera, album strip) over its
/// input, split front/back by each source's subject mask, bottom route first.
/// `feed` (before cell) passes the cell routes into the automata input;
/// `router` (after color) passes the real color routes over the pal color;
/// the SD-Turbo state (2) routes nowhere until DeepMuse has SD-Turbo.
/// Route state lives in `pipe.router.<source>.{front,back,fade}`, front = path a, back = path b:
/// front/back x = the outputs the path is routed to, one bit each (1 raw, 2 pal,
/// the cell rule, 4 SD-Turbo; 0 empty, 3 raw and pal both), y = z order 1…6,
/// w = the part of a masked source the path carries (1 F the subject, 2 B the
/// rest, 3 F+B the whole frame unmasked; path a starts on F, path b on B),
/// z = that path's opacity 0…1 (the layers leaf slider), applied in whichever pass
/// draws it; fade x = the source master. The camera's is canvas.mix's fade,
/// pal to the camera's output, wherever that is routed: pal·(1−x) + camera·x
/// where the camera covers, the strokes and the album left as they are. On
/// Pal the camera is faded into the cell rule's input: the feed pass
/// multiplies its paths by x. On Raw with the mix wheel on real over pal the
/// router pass does the same, the camera at x over the pal layer. With pal
/// over real that would only dim the camera under the pal, so there the
/// camera's paths keep their own sliders and the pal layer thins over the
/// camera instead, by x times the camera's share of the real layer (`blend`,
/// `palOverCamera`).
/// draw's back lane is the pal canvas, shown by the router pass on raw or pal.
public class RouterNode: ComputeNode {

    struct SourceUniform {
        var route = SIMD4<Float>(0, 6, 0, 3)   // front outputs, front z order, back outputs, back z order
        var fade  = SIMD4<Float>(1, 0, 0, 1)   // front fade, has mask, has texture, back fade
        var part  = SIMD4<Float>(1, 2, 0, 0)   // front part, back part: 1 F, 2 B, 3 F+B unmasked
    }
    struct Uniforms {
        var pass = SIMD4<Float>(1, 0, 0, 0)    // x = the output bit this pass composites: 1 raw, 2 pal; y camera, z album: 1 = joined
        var draw = SourceUniform()
        var camera = SourceUniform()
        var album = SourceUniform()
        var luma = SIMD4<Float>(1, 1, 0, 0)   // pal disk mix: real level, pal level, black key, 0 off 1 real on top 2 pal on top
        var curve = RouterNode.curveUniform(.identity) // the mix key's cut edge: x its half width
        var range = SIMD4<Float>(0, 1, 0, 1) // each layer's measured luma: real lo hi, pal lo hi
        var blend = SIMD4<Float>(1, 0, 0, 0) // canvas.mix's fade where pal is over a raw camera: x pal 0 to camera 1, y 1 = the pal layer thins over the camera by it
    }

    /// each layer's luma range as the kernel measured it, read back three
    /// frames late from a ring so the GPU is done with it, and eased so a
    /// stroke entering the layer widens the range over a few frames
    final class LumaRange {
        private var bufs = [MTLBuffer]()
        private var index = 0
        private(set) var range = SIMD4<Float>(0, 1, 0, 1)
        static let ease: Float = 0.15

        init(_ device: MTLDevice) {
            for _ in 0 ..< 3 {
                if let buf = device.makeBuffer(length: 16, options: .storageModeShared) {
                    Self.clear(buf)
                    bufs.append(buf)
                }
            }
        }
        private static func clear(_ buf: MTLBuffer) {
            let p = buf.contents().bindMemory(to: UInt32.self, capacity: 4)
            p[0] = 65535; p[1] = 0; p[2] = 65535; p[3] = 0
        }
        /// the oldest buffer: fold what it measured into the range, clear it, hand it out
        func next() -> MTLBuffer? {
            guard !bufs.isEmpty else { return nil }
            index = (index + 1) % bufs.count
            let buf = bufs[index]
            let p = buf.contents().bindMemory(to: UInt32.self, capacity: 4)
            func fold(_ i: Int, _ lo: UInt32, _ hi: UInt32) {
                guard lo <= hi else { return } // the layer held nothing
                let target = SIMD2(Float(lo), Float(hi)) / 65535
                let now = SIMD2(range[i], range[i + 1])
                let eased = now + (target - now) * Self.ease
                range[i] = eased.x; range[i + 1] = eased.y
            }
            fold(0, p[0], p[1])
            fold(2, p[2], p[3])
            Self.clear(buf)
            return buf
        }
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
            RouteSource(code: code, route: u.route, lane: lane, master: master,
                        part: SIMD2(u.part.x, u.part.y))
        }
        /// the lane's w, 1…3; a lane with none (draw's, an older script's) keeps its home
        static func part(_ lane: Flo?, _ home: Float) -> Float {
            let w = Float(lane?.val("w") ?? 0).rounded()
            return (1...3).contains(w) ? w : home
        }
        func uniform() -> SourceUniform {
            var u = SourceUniform()
            u.route = SIMD4(Float(front˚?.val("x") ?? 0), Float(front˚?.val("y") ?? 6),
                            Float(back˚?.val("x") ?? 0),  Float(back˚?.val("y") ?? 3))
            u.part = SIMD4(Self.part(front˚, 1), Self.part(back˚, 2), 0, 0)
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
    private var luma˚    : Flo?   // pipe.router.draw.luma <> canvas.luma: the pal disk mix, router pass only
    private var lumaRange: LumaRange!
    private var lumaCurve˚: Flo?  // pipe.router.draw.lumaCurve <> canvas.lumaCurve: the key's depth and breadth
    private var lastStack = SIMD2<Float>(-1, -1) // mix order, key end: log transitions only
    private var routeLog = RouteLog()             // the route as the frames read it, one line a change

    /// one source as the Layers leaf shows it: its row's code, its route
    /// (front outputs, front z, back outputs, back z), its two opacity sliders,
    /// the master fade the kernel multiplies both by (canvas.mix fade for
    /// the camera) -- kept apart so the log's opacity is the slider's own --
    /// and the part each path carries (1 F, 2 B, 3 F+B)
    struct RouteSource: Equatable {
        var code: String
        var route: SIMD4<Float>
        var lane: SIMD2<Float>
        var master: Float = 1
        var part = SIMD2<Float>(1, 2)
    }
    /// is a path with these outputs composited by the pass that draws `pass`
    static func routed(_ outputs: Float, _ pass: Float) -> Bool {
        Int(outputs) & Int(pass) != 0
    }
    private static func partLabel(_ part: Float) -> String {
        part > 2.5 ? "F+B" : part > 1.5 ? "B" : "F"
    }
    /// the route in the Layers leaf's compact notation, the row order top first,
    /// each opacity slider, and any master fade that isn't 1:
    /// `DF1B0,CF3B0,AF1B1 · order A,C,D · opacity DF 0.00 DB 1.00 … · fade C 0.50`,
    /// and a path carrying another part than its own: `· part CF F+B`
    static func routeLine(_ sources: [RouteSource]) -> String {
        let code = sources.map { "\($0.code)F\(Int($0.route.x))B\(Int($0.route.z))" }.joined(separator: ",")
        let opacities = sources.map {
            "\($0.code)F \(digits($0.lane.x)) \($0.code)B \(digits($0.lane.y))"
        }.joined(separator: " ")
        let fades = sources.filter { digits($0.master) != digits(1) }
            .map { "\($0.code) \(digits($0.master))" }.joined(separator: " ")
        var parts = [String]()
        for s in sources {
            if s.part.x != 1 { parts.append("\(s.code)F \(partLabel(s.part.x))") }
            if s.part.y != 2 { parts.append("\(s.code)B \(partLabel(s.part.y))") }
        }
        var line = "\(code) · order \(order(sources)) · opacity \(opacities)"
        if !fades.isEmpty { line += " · fade \(fades)" }
        if !parts.isEmpty { line += " · part \(parts.joined(separator: " "))" }
        return line
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
        for s in sources {
            fields.append(RouteField(key: "\(s.code)F part", value: partLabel(s.part.x)))
            fields.append(RouteField(key: "\(s.code)B part", value: partLabel(s.part.y)))
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

    /// the pal disk mix as the kernel reads it: both key levels, the key end,
    /// and which whole layer is on top -- real (every real color route) or pal
    static func lumaUniform(_ mix: LumaMix) -> SIMD4<Float> {
        SIMD4(mix.realLevel, mix.palLevel, mix.black ? 1 : 0, mix.realOnTop ? 1 : 2)
    }
    /// the mix key's cut edge as the kernel reads it: its half width over luma
    static func curveUniform(_ mix: LumaMix) -> SIMD4<Float> {
        SIMD4(mix.band, 0, 0, 0)
    }
    /// the pal disk point and the key's curve, script defaults where unbound
    static func lumaMix(_ luma˚: Flo, _ curve˚: Flo?) -> LumaMix {
        LumaMix(x: luma˚.val("x") ?? 0.5, y: luma˚.val("y") ?? 1,
                depth: curve˚?.val("depth") ?? LumaMix.defaultDepth,
                breadth: curve˚?.val("breadth") ?? LumaMix.defaultBreadth)
    }

    /// is the camera part of the real layer: running, with a path on Raw
    static func cameraInReal(_ c: SourceUniform) -> Bool {
        c.fade.z > 0.5 && (routed(c.route.x, 1) || routed(c.route.z, 1))
    }
    /// canvas.mix's fade where the mix wheel puts pal over real, as the kernel
    /// applies it: the part of the pal layer's opacity left over the camera.
    /// `share` is the camera's visible share of the real layer at that pixel,
    /// 0 where it holds nothing or a stroke covers it, so the pal over the
    /// strokes and the album stays whole; over the whole camera the two mix
    /// pal·(1−x) + camera·x, as the camera at x over pal does the other way round
    static func palOverCamera(_ fade: Float, share: Float) -> Float {
        1 - fade * share
    }
    /// the router pass under the mix wheel, the camera on Raw. Real over pal:
    /// canvas.mix's fade stays on the camera's paths, the camera at x over the
    /// pal layer. Pal over real: the paths go back to their own sliders and
    /// the fade is the pal layer's over the camera
    static func blend(_ camera: inout SourceUniform, lane: SIMD2<Float>, master: Float,
                      realOnTop: Bool) -> SIMD4<Float> {
        guard !realOnTop, cameraInReal(camera) else { return SIMD4(1, 0, 0, 0) }
        camera.fade.x = lane.x
        camera.fade.w = lane.y
        return SIMD4(master, 1, 0, 0)
    }

    /// a masked source whose front and back both composite in this pass, one
    /// carrying F and the other B, with no visible route between them, is drawn
    /// once as one layer, coverage front·m + back·(1−m). Two composites let what
    /// lies beneath show through the mask's soft edge as base·m(1−m), the cell
    /// canvas's noise in the seam; joined, front 1 back 1 is the whole frame,
    /// unseparated. A path on F+B is whole by itself and joins nothing
    static func joined(_ u: Uniforms) -> (camera: Bool, album: Bool) {
        let pass = u.pass.x
        let d = u.draw, c = u.camera, a = u.album
        func lane(_ s: SourceUniform, _ front: Bool) -> Bool {
            s.fade.z > 0.5 && routed(front ? s.route.x : s.route.z, pass)
        }
        // the two paths carry the two halves of the mask, F and B, either way round
        func halves(_ s: SourceUniform) -> Bool {
            (s.part.x == 1 && s.part.y == 2) || (s.part.x == 2 && s.part.y == 1)
        }
        // routerKernel's composites in its order: z, then draw front, pal canvas,
        // camera front, back, album front, back; nil = none visible in this pass
        func slot(_ z: Float, _ order: Int, _ on: Bool) -> Int? { on ? Int(z) * 8 + order : nil }
        let slots = [slot(d.route.y, 0, d.fade.z > 0.5 && routed(d.route.x, pass) && d.fade.x > 0),
                     slot(d.route.w, 1, pass == 1 && routed(d.route.z, 3) && d.fade.w > 0),
                     slot(c.route.y, 2, lane(c, true) && c.fade.x > 0),
                     slot(c.route.w, 3, lane(c, false) && c.fade.w > 0),
                     slot(a.route.y, 4, lane(a, true) && a.fade.x > 0),
                     slot(a.route.w, 5, lane(a, false) && a.fade.w > 0)]
        func join(_ s: SourceUniform, _ front: Int, _ back: Int) -> Bool {
            guard s.fade.y > 0.5, lane(s, true), lane(s, false), halves(s) else { return false }
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

        pass = pipeNode˚.name == "feed" ? 2 : 1 // the output bit it composites: pal into the cell rule, raw over the color
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
        lumaRange = LumaRange(pipeline.device)
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
        let mix = luma˚.map { RouterNode.lumaMix($0, lumaCurve˚) }
        if let mix {
            u.blend = RouterNode.blend(&u.camera, lane: camera.lane, master: camera.master,
                                       realOnTop: mix.realOnTop)
        }
        #if DEBUG
        if pass == 1, let line = routeLog.frame([draw.routeSource("D", u.draw),
                                                  camera.routeSource("C", u.camera),
                                                  album.routeSource("A", u.album)]) {
            DebugLog { P("🔀 route \(line)") }
        }
        #endif
        var joinable = u
        if let mix {
            u.luma = RouterNode.lumaUniform(mix)
            u.curve = RouterNode.curveUniform(mix)
            if SIMD2(u.luma.w, u.luma.z) != lastStack {
                lastStack = SIMD2(u.luma.w, u.luma.z)
                let top = lastStack.x < 1.5 ? "real over pal" : "pal over real"
                let key = lastStack.y > 0.5 ? "B" : "W"
                DebugLog { P("🔀 router mix \(top), key \(key)") }
            }
            // under the mix the pal canvas is a layer of its own, not a route between
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
        let stats = lumaRange.next()
        if luma˚ != nil { u.range = lumaRange.range }
        encoder.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setBuffer(stats, offset: 0, index: 1)
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
