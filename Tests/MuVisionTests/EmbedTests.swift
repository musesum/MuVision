//  created by musesum on 8/6/26.

import XCTest
import Metal
@testable import MuVision

final class EmbedTests: XCTestCase {

    let template = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void testKernel(
     texture2d<float, access::write> outTex [[ texture(0) ]],
     uint2 gid [[thread_position_in_grid]])
    {
        {{ // test
            outTex.write(float4(0,1,0,1), gid);
        }}
    }
    """

    func testStitchOffset() throws {
        let body = "\n outTex.write(float4(1,0,0,1), gid);\n "
        let stitched = try Shader.stitch(template, body: body)
        XCTAssertEqual(stitched.bodyLine, 7)
        XCTAssertTrue(stitched.source.contains("float4(1,0,0,1)"))
        XCTAssertFalse(stitched.source.contains("float4(0,1,0,1)"))
    }
    func testStitchRejectsDoubleClose() {
        XCTAssertThrowsError(try Shader.stitch(template, body: "if (a) { if (b) { c; }}")) {
            XCTAssertEqual($0 as? StitchError, .bodyClosesEmbed)
        }
    }
    func testEmbedErrorMapping() {
        let log = "program_source:10:5: error: use of undeclared identifier 'boom'"
        let errors = Shader.embedErrors(log, bodyLine: 7)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.line, 4)
        XCTAssertEqual(errors.first?.col, 5)
    }
    func testRuntimeCompileDispatch() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let body = "\n outTex.write(float4(1,0,0,1), gid);\n "
        let stitched = try Shader.stitch(template, body: body)
        let library = try device.makeLibrary(source: stitched.source, options: MTLCompileOptions())
        let function = try XCTUnwrap(library.makeFunction(name: "testKernel"))
        let pso = try device.makeComputePipelineState(function: function)

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        texDesc.usage = [.shaderWrite, .shaderRead]
        let tex = try XCTUnwrap(device.makeTexture(descriptor: texDesc))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commands.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pso)
        encoder.setTexture(tex, index: 0)
        encoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: 4, height: 4, depth: 1))
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()

        var pixel = [UInt8](repeating: 0, count: 4)
        tex.getBytes(&pixel, bytesPerRow: 16,
                     from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        XCTAssertEqual(pixel[0], 255) // red from stitched body, not template's green
        XCTAssertEqual(pixel[1], 0)
    }
    func testCompileErrorMapsToBodyLine() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let body = "\n boom();\n "
        let stitched = try Shader.stitch(template, body: body)
        do {
            _ = try device.makeLibrary(source: stitched.source, options: MTLCompileOptions())
            XCTFail("expected compile failure")
        } catch {
            let errors = Shader.embedErrors(error.localizedDescription,
                                            bodyLine: stitched.bodyLine)
            XCTAssertGreaterThan(errors.count, 0)
            XCTAssertEqual(errors.first?.line, 2) // boom() is body line 2
        }
    }
}
