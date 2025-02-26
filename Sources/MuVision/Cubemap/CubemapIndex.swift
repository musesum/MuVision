//  created by musesum on 3/2/23.

import Foundation

/** Instead of copying a video texture into 6 cube faces,
 precompute an index cube that points to a pixel
 on the original 2D texture.

    |                 left+90 ║ top   ║ right-90
    |                 ════════╝       ╚══════════════
    |                 left     center   right    back
    |                 ════════╗       ╔══════════════
    |                 left-90 ║  bot  ║ right+90

    | here is a mapping of a 6x6 cube index
    | numbers shorten (x,y) as xy. For example, (1,2) as 12

    |  55 54 53 52 51 50 ║ 50 40 30 20 10 00 ║ 00 01 02 03 04 05
    |  45 44 43 42 41 40 ║ 40 41 31 21 11 10 ║ 10 11 12 13 14 15
    |  35 34 33 32 31 30 ║ 30 31 32 22 21 20 ║ 20 21 22 23 24 25
    |  25 24 23 22 21 20 ║ 20 21 22 32 31 30 ║ 30 31 32 33 34 35
    |  15 14 13 12 11 10 ║ 10 11 21 31 41 40 ║ 40 41 42 43 44 45
    |  05 04 03 02 01 00 ║ 00 10 20 30 40 50 ║ 50 51 52 53 54 55
    |  ══════════════════╝                   ╚══════════════════════════════════════
    |  50 40 30 20 10 00   00 10 20 30 40 50   50 40 30 20 10 00   00 10 20 30 40 50
    |  51 41 31 21 11 01   01 11 21 31 41 51   51 41 31 21 11 01   01 11 21 31 41 51
    |  52 42 32 22 12 02   02 12 22 32 42 52   52 42 32 22 12 02   02 12 22 32 42 52
    |  53 43 33 23 13 03   03 13 23 33 43 53   53 43 33 23 13 03   03 13 23 33 43 53
    |  54 44 34 24 14 04   04 14 24 34 44 54   54 44 34 24 14 04   04 14 24 34 44 54
    |  55 45 35 25 15 05   05 15 25 35 45 55   55 45 35 25 15 05   05 15 25 35 45 55
    |  ══════════════════╗                   ╔══════════════════════════════════════
    |  00 01 02 03 04 05 ║ 05 15 25 35 45 55 ║ 55 54 53 52 51 50
    |  10 11 12 13 14 15 ║ 15 14 24 34 44 45 ║ 45 44 43 42 41 40
    |  20 21 22 23 24 25 ║ 25 24 23 33 34 35 ║ 35 34 33 32 31 30
    |  30 31 32 33 34 35 ║ 35 34 33 23 24 25 ║ 25 24 23 22 21 20
    |  40 41 42 43 44 45 ║ 45 44 34 24 14 15 ║ 15 14 13 12 11 10
    |  50 51 52 53 54 55 ║ 55 45 35 25 15 05 ║ 05 04 03 02 01 00

    |  front (.nw_ne_c)
    |  00 10 20 30 40 50
    |     11 21 31 41
    |       22 32

    |  top (.ne_nw_c)
    |  50 40 30 20 10 00
    |     41 21 31 11
    |        32 22

    |  mapped from (.nw_ne_c) to (.ne_nw_c)
    |  front:  [00 10 20 30 40 50 11 21 31 41 22 32]
    |  top:    [50 40 30 20 10 00 41 21 31 11 32 22]

    |  here is the process of making the top Quad from 4 Tris

    |  src: 50 40 30 20 10 00 41 31 21 11 32 22
    |  dst: 00 10 20 30 40 50 11 21 31 41 22 32

    |  50 40 30 20 10 00
    |  -- 41 31 21 11 --
    |  -- -- 32 22 -- --
    |  -- -- -- -- -- --
    |  -- -- -- -- -- --
    |  -- -- -- -- -- --

    |  src: 00 10 20 30 40 50 11 21 31 41 22 32
    |  dst: 50 51 52 53 54 55 41 42 43 44 32 33

    |  50 40 30 20 10 00
    |  -- 41 31 21 11 10
    |  -- -- 32 22 21 20
    |  -- -- -- 32 31 30
    |  -- -- -- -- 41 40
    |  -- -- -- -- -- 50

    |  src: 50 40 30 20 10 00 41 31 21 11 32 22
    |  dst: 55 45 35 25 15 05 44 34 24 14 33 23

    |  50 40 30 20 10 00
    |  -- 41 31 21 11 10
    |  -- -- 32 22 21 20
    |  -- -- 22 32 31 30
    |  -- 11 21 31 41 40
    |  00 10 20 30 40 50

    |  src: 00 10 20 30 40 50 11 21 31 41 22 32
    |  dst: 05 04 03 02 01 00 14 13 12 11 23 22

    |  50 40 30 20 10 00
    |  40 41 31 21 11 10
    |  30 31 32 22 21 20
    |  20 21 22 32 31 30
    |  10 11 21 31 41 40
    |  00 10 20 30 40 50
 */
public typealias FloatRG16 = (Float16,Float16)
public typealias Quad = [FloatRG16]

class CubemapIndex {


    var size = CGSize.zero
    var side: Int // side length of square

    var count = 0 // side x side
    var logging = false
    var testing = false

    var top   : Quad
    var back  : Quad
    var right : Quad
    var front : Quad
    var left  : Quad
    var bot   : Quad

    enum CubeTriangle: Int { case

        // clock, counter
        nw_ne_c, ne_nw_c,
        ne_se_c, se_ne_c,
        se_sw_c, sw_se_c,
        sw_nw_c, nw_sw_c,
        maximum
    }

    var cubeTriangles = [CubeTriangle: [FloatRG16]]()
    /// triangle order for mapping `front` to other Quads
    //  front : [.nw_ne_c, .ne_se_c, .se_sw_c, .sw_nw_c]
    //  back  : [.nw_ne_c, .ne_se_c, .se_sw_c, .sw_nw_c]
    //  left  : [.ne_nw_c, .nw_sw_c, .sw_se_c, .se_ne_c]
    //  right : [.ne_nw_c, .nw_sw_c, .sw_se_c, .se_ne_c]
    //  top   : [.ne_nw_c, .nw_ne_c, .ne_nw_c, .nw_ne_c]
    //  bot   : [.sw_se_c, .se_sw_c, .sw_se_c, .se_sw_c]

    init(_ size: CGSize,
         logging: Bool = false,
         testing: Bool = false) {

        self.size = size
        self.logging = logging
        self.testing = testing

        side = Int(min(size.width, size.height, 2048))
        count = side * side

        top   = [FloatRG16](repeating: (-1,-1), count: count)
        back  = [FloatRG16](repeating: (-1,-1), count: count)
        right = [FloatRG16](repeating: (-1,-1), count: count)
        front = [FloatRG16](repeating: (-1,-1), count: count)
        left  = [FloatRG16](repeating: (-1,-1), count: count)
        bot   = [FloatRG16](repeating: (-1,-1), count: count)

        makeCubeTris()
        makeSides()
        makeTop()
        makeBot()
        shiftOffsets()

        if testing {
            makeLeft() // see comment
        }
    }

    func shiftOffsets() {
        let xs = size.width
        let ys = size.height
        let ss = CGFloat(side)
        let xOfs = Float16(((xs - ss) / 2) / xs)
        let yOfs = Float16(((ys - ss) / 2) / ys)

        shiftOffset(&top  )
        shiftOffset(&back )
        shiftOffset(&right)
        shiftOffset(&front)
        shiftOffset(&left )
        shiftOffset(&bot  )

        func shiftOffset(_ nums: inout [FloatRG16]) {

            for i in 0..<nums.count {
                let num = nums[i]
                let x = CGFloat(num.0)
                let y = CGFloat(num.1)
                nums[i] = (Float16(xOfs + Float16(x/xs)),
                           Float16(yOfs + Float16(y/ys)))
            }
        }
    }
    func floatRG16(_ x: Int,_ y: Int) -> FloatRG16 {
        (Float16(x),Float16(y))
    }
    /// make front, back, left, right
    func makeSides() {
        for x in 0 ..< side {
            for y in 0 ..< side {
                let yi = y * side
                let xm = Int(side-x-1)

                front [yi +  x] = floatRG16(x, y)
                back  [yi +  x] = floatRG16(x, y)
                left  [yi + xm] = floatRG16(x, y)
                right [yi + xm] = floatRG16(x, y)
            }
        }
        // logBorder("front ", front )
        // logBorder("left  ", left  )
        // logBorder("right ", right )
        // logBorder("back  ", back  )
    }
    /// from: front to: top quadrant tris
    func makeTop() {
        mapTris(.ne_nw_c, to: .nw_ne_c, &top) // ; logQuad(top);
        mapTris(.nw_ne_c, to: .ne_se_c, &top) // ; logQuad(top);
        mapTris(.ne_nw_c, to: .se_sw_c, &top) // ; logQuad(top);
        mapTris(.nw_ne_c, to: .sw_nw_c, &top) // ; logQuad(top);
    }
    /// from: front to: bot quadrant tris
    func makeBot() {
        mapTris(.sw_se_c, to: .nw_ne_c, &bot) // ; logQuad(bot);
        mapTris(.se_sw_c, to: .ne_se_c, &bot) // ; logQuad(bot);
        mapTris(.sw_se_c, to: .se_sw_c, &bot) // ; logQuad(bot);
        mapTris(.se_sw_c, to: .sw_nw_c, &bot) // ; logQuad(bot);
    }
    /// from: front to: left quadrant tris.
    ///
    /// - note: even though this is redundant with makeSides(),
    /// is useful to test some of the other Tri mappings
    /// which are not used by makeTop() or makeBot()
    func makeLeft() {
        mapTris(.ne_nw_c, to: .nw_ne_c, &left) // ; logQuad(left);
        mapTris(.nw_sw_c, to: .ne_se_c, &left) // ; logQuad(left);
        mapTris(.sw_se_c, to: .se_sw_c, &left) // ; logQuad(left);
        mapTris(.se_ne_c, to: .sw_nw_c, &left) // ; logQuad(left);
    }

    func mapTris(_  srcTri : CubeTriangle,
                 to dstTri : CubeTriangle,
                 _  quad   : inout Quad ) {

        if let srcIndices = cubeTriangles[srcTri],
           let dstIndices = cubeTriangles[dstTri] {

            logIndices(srcIndices, dstIndices)

            for i in 0 ..< srcIndices.count {
                let srcIndex = srcIndices[i]
                let dstIndex = dstIndices[i]
                let address = Int(dstIndex.0) + Int(dstIndex.1) * side
                quad[address] = srcIndex
            }
        }
    }

    func logIndices( _ src: [FloatRG16], _ dst: [FloatRG16]) {
        if logging {
            print("src:", terminator: " ")
            for xy in src {
                print("\(xy.0)\(xy.1)", terminator: " ")
            }
            print("\ndst:", terminator: " ")
            for xy in dst {
                print("\(xy.0)\(xy.1)", terminator: " ")
            }
            print("\n")
        }
    }

    // make an index cube for square where side == width and height
    func makeCubeTris() {

        let S = side - 1 // last index of s
        let S2 = S/2

        // first create trianglar index arrays
        cubeTriangles[.nw_ne_c] = make_nw_ne_c()
        cubeTriangles[.ne_nw_c] = make_ne_nw_c()
        cubeTriangles[.ne_se_c] = make_ne_se_c()
        cubeTriangles[.se_ne_c] = make_se_ne_c()
        cubeTriangles[.se_sw_c] = make_se_sw_c()
        cubeTriangles[.sw_se_c] = make_sw_se_c()
        cubeTriangles[.sw_nw_c] = make_sw_nw_c()
        cubeTriangles[.nw_sw_c] = make_nw_sw_c()

        // these are the triangle mapped to face of cube
        // next fill each face with indices to front face

        func make_nw_ne_c() -> [FloatRG16] {
            var r = [FloatRG16]()
            for i in 0 ... S2 {
                for j in i ... S-i {
                    r.append(floatRG16(j,i))
                }
            }
            return r
        }
        func make_ne_nw_c() -> [FloatRG16] {
            var r = [FloatRG16]()
            for i in 0 ... S2 {
                for j in (i ... S-i) {
                    r.append(floatRG16(S-j, i))
                }
            }
            return r
        }
        func make_ne_se_c() -> [FloatRG16] {
            var r = [FloatRG16]()
            for i in 0 ... S2 {
                for j in i ... S-i {
                    r.append(floatRG16(S-i, j))
                }
            }
            return r
        }
        func make_se_ne_c() -> [FloatRG16] {
            var r = [FloatRG16]()
            for i in 0 ... S2 {
                for j in (i ... S-i) {
                    r.append(floatRG16(S-i, S-j))
                }
            }
            return r
        }
        func make_sw_se_c() -> [FloatRG16] {
            var r = [FloatRG16]()
            for i in 0 ... S2 {
                for j in i ... S-i {
                    r.append(floatRG16(j, S-i))
                }
            }
            return r
        }
        func make_se_sw_c() -> [FloatRG16] {
            var r = [FloatRG16]()
            for i in 0 ... S2 {
                for j in i ... S-i {
                    r.append(floatRG16(S-j, S-i))
                }
            }
            return r
        }
        func make_sw_nw_c() -> [FloatRG16] {
            var r = [FloatRG16]()
            for i in 0 ... S2 {
                for j in i ... S-i {
                    r.append(floatRG16(i, S-j))
                }
            }
            return r
        }
        func make_nw_sw_c() -> [FloatRG16] {
            var r = [FloatRG16]()
            for i in 0 ... S2 {
                for j in i ... S-i {
                    r.append(floatRG16(i, j))
                }
            }
            return r
        }
    }

    func logBorder(_ title: String, _ quad: Quad) {

        var str = title + ":"
        let n = side-1
        addXY("0,0", 0,0)
        addXY("0,n", 0,n)
        addXY("n,n", n,n)
        addXY("n,0", n,0)
        addXY("m,m", n-1,n-1)
        addXY("1,1", 1,1)

        func addXY(_ title: String, _ x: Int, _ y: Int) {
            let address = x + y*side
            let q = quad[address]
            str += " [\(title)](\(Int(q.0)),\(Int(q.1)))"
        }
        print(str)
    }

    func logQuad(_ quad: Quad) {
        if logging {
            print(scriptQuad(quad)+"\n")
        }
    }
    func scriptQuad(_ quad: Quad) -> String {
        var str = ""
        var del = "" // delimiter
        for y in 0 ..< side {
            for x in 0 ..< side {
                let address = x + y*side
                let q = quad[address]
                if q.0 < 0 {
                    str += del + "--"
                } else {
                    str += del + "\(q.0),\(q.1)"
                }
                del = " "
            }
            str += "\n"
            del = ""
        }
        return str
    }
    static func compare(_ str1: String, _ str2: String) -> Int {
        return str1 == str2 ? 0 : 1
    }
    static func testCubeDex() {

        let topStr =
        """
        50 40 30 20 10 00
        40 41 31 21 11 10
        30 31 32 22 21 20
        20 21 22 32 31 30
        10 11 21 31 41 40
        00 10 20 30 40 50

        """ // keep blank line

        let backStr =
        """
        00 10 20 30 40 50
        01 11 21 31 41 51
        02 12 22 32 42 52
        03 13 23 33 43 53
        04 14 24 34 44 54
        05 15 25 35 45 55

        """  // keep blank line

        let rightStr =
        """
        50 40 30 20 10 00
        51 41 31 21 11 01
        52 42 32 22 12 02
        53 43 33 23 13 03
        54 44 34 24 14 04
        55 45 35 25 15 05

        """  // keep blank line

        let frontStr =
        """
        00 10 20 30 40 50
        01 11 21 31 41 51
        02 12 22 32 42 52
        03 13 23 33 43 53
        04 14 24 34 44 54
        05 15 25 35 45 55

        """  // keep blank line

        let leftStr =
        """
        50 40 30 20 10 00
        51 41 31 21 11 01
        52 42 32 22 12 02
        53 43 33 23 13 03
        54 44 34 24 14 04
        55 45 35 25 15 05

        """  // keep blank line

        let botStr =
        """
        05 15 25 35 45 55
        15 14 24 34 44 45
        25 24 23 33 34 35
        35 34 33 23 24 25
        45 44 34 24 14 15
        55 45 35 25 15 05

        """  // keep blank line

        let cubemapIndex = CubemapIndex(CGSize(width: 6,height: 6))
        var err = 0
        err += compare(cubemapIndex.scriptQuad(cubemapIndex.top  ), topStr  )
        err += compare(cubemapIndex.scriptQuad(cubemapIndex.bot  ), botStr  )
        err += compare(cubemapIndex.scriptQuad(cubemapIndex.front), frontStr)
        err += compare(cubemapIndex.scriptQuad(cubemapIndex.left ), leftStr )
        err += compare(cubemapIndex.scriptQuad(cubemapIndex.right), rightStr)
        err += compare(cubemapIndex.scriptQuad(cubemapIndex.back ), backStr )

        print (err == 0
               ? "CubemapIndex test passed"
               : "CubemapIndex test has \(err) errors")
    }
}

/// A Float version of CubeDex to build cube in shader
///
///    not used
///
class CubeVert {

    let NW = SIMD2<Float>(0,0)
    let NE = SIMD2<Float>(1,0)
    let SW = SIMD2<Float>(0,1)
    let SE = SIMD2<Float>(1,1)
    let C  = SIMD2<Float>(0.5,0.5)

    typealias Tri2 = (SIMD2<Float>,SIMD2<Float>,SIMD2<Float>)
    typealias QuadTri2 = (Tri2,Tri2,Tri2,Tri2)

    var Front : QuadTri2
    var Top   : QuadTri2
    var Left  : QuadTri2
    var Right : QuadTri2
    var Back  : QuadTri2
    var Bot   : QuadTri2

    init() {

        Front = ((NW,NE,C),(NE,SE,C),(SE,SW,C),(SW,NW,C))
        Top   = ((NE,NW,C),(NW,NE,C),(NE,NW,C),(NW,NE,C))
        Left  = ((NE,NW,C),(NW,SW,C),(SW,SE,C),(SE,NE,C))
        Right = ((NE,NW,C),(NW,SW,C),(SW,SE,C),(SE,NE,C))
        Back  = ((NW,NE,C),(NE,SE,C),(SE,SW,C),(SE,NW,C))
        Bot   = ((SW,SE,C),(SE,SW,C),(SW,SE,C),(SE,SW,C))
    }
}
