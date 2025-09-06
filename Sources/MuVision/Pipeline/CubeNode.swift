//  created by musesum on 3/16/23.

import UIKit
import Metal
import CoreImage
import simd
import ModelIO
import MetalKit
#if os(visionOS)
import CompositorServices
#endif
import MuFlo

public struct VertexCube {
    var position : vector_float4 = .zero
}

public class CubeNode: RenderNode, @unchecked Sendable {

    private let viaIndex   : Bool
    internal var cubeMesh  : CubeMesh!
    internal var cubeIndex : CubemapIndex?
    internal var inTex˚    : Flo?
    internal var cudex˚    : Flo?
    private var displace˚  : Flo?
    internal var mixcube˚  : Flo?
    private var lastAspect : Aspect?

    internal var bakePipelineState: MTLRenderPipelineState!
    internal var scratch0: MTLTexture?   // throwaway for MRT color0 when baking

    override public init(_ pipeline : Pipeline,
                         _ pipeFlo˚ : Flo) {

        self.cubeMesh = CubeMesh(pipeline.renderState)
        self.viaIndex = true
        super.init(pipeline, pipeFlo˚)
        
        inTex˚    = pipeFlo˚.superBindPath("in")
        cudex˚    = pipeFlo˚.superBindPath("cudex")
        displace˚ = pipeFlo˚.superBindPath("displace")
        mixcube˚  = pipeFlo˚.superBindPath("mixcube")
        makeRenderPipeline()
        makeResources()
        pipeline.rotateClosure["cudex˚"] = { self.makeCube() }
    }
    
    func makeRenderPipeline() {
        shader = Shader(pipeline,
                        file: "render.map.cube",
                        vertex: "cubeVertex",
                        fragment: "cubeIndexFragment")
        renderPipelineState = makeRenderState(cubeMesh.metalVD)
    }

    func makeCube() {

        if let lastAspect, lastAspect == pipeline.pipeSize.aspect { return }
        self.lastAspect = pipeline.pipeSize.aspect

        if let tex = makeCubeTex(), let cudex˚ {
            cudex˚.texture = tex
            cudex˚.reactivate()
        }

        func makeCubeTex() -> MTLTexture? {
            if viaIndex {
                let label = cudex˚?.path(3) ?? "cudex"
                return  makeIndexCube(pipeline.pipeSize, label)
            } else {
                let facenames = ["front", "front", "top", "bottom", "front", "front"]
                return makeImageCube(facenames)
            }
        }
    }
    override open func makeResources() {

        makeCube()
        cubeMesh.eyeBuf = EyeBuf("CubeEyes", far: false)
#if os(visionOS)
        makeBakePipeline() //..... ← add
#endif
        super.makeResources()
    }

    override open func renderShader(_ renderEnc: MTLRenderCommandEncoder,
                                    _ renderState: RenderState) {
        guard let renderPipelineState else { return }

        cubeMesh.eyeBuf?.setUniformBuf(renderEnc)
        if let mixcube˚ {
            #if os(visionOS) //....
            mixcube˚.setNameNums([("x", 1)], .fire) //....
            #endif
            mixcube˚.updateMtlBuffer()
        }
        //.... renderEnc.setFragmentTexture(displace˚,index: 3)
        renderEnc.setFragmentTexture(inTex˚,   index: 0)
        renderEnc.setFragmentTexture(cudex˚,   index: 1)
        renderEnc.setFragmentBuffer (mixcube˚, index: 0)

        renderEnc.setRenderPipelineState(renderPipelineState)
        cubeMesh.drawMesh(renderEnc, renderState)
        cudex˚?.reactivate()
    }

    func makeImageCube(_ names: [String]) -> MTLTexture? {

        let image0 = UIImage(named: names[0])!
        let imageW = Int(image0.size.width)
        let cubeLength = imageW * Int(image0.scale)

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * imageW
        let bytesPerImage = bytesPerRow * cubeLength
        let region = MTLRegionMake2D(0, 0, cubeLength, cubeLength)

        let td = MTLTextureDescriptor
            .textureCubeDescriptor(pixelFormat : .bgra8Unorm,
                                   size        : cubeLength,
                                   mipmapped   : true)
        let texture = pipeline.device.makeTexture(descriptor: td)!

        for slice in 0 ..< 6 {
            let image = UIImage(named: names[slice])!
            let data = image.cgImage!.pixelData()

            texture.replace(region        : region,
                            mipmapLevel   : 0,
                            slice         : slice,
                            withBytes     : data!,
                            bytesPerRow   : bytesPerRow,
                            bytesPerImage : bytesPerImage)
        }
        return texture
    }
    @inline(__always)
    func makeIndexCube(_ size: CGSize,
                       _ label: String) -> MTLTexture? {

        if cubeIndex?.size != size {
            cubeIndex = CubemapIndex(size)
        }
        guard let cubeIndex else { return nil }

        let td = MTLTextureDescriptor
            .textureCubeDescriptor(pixelFormat : .rg16Float,
                                   size        : cubeIndex.side,
                                   mipmapped   : true)
        let texture = pipeline.device.makeTexture(descriptor: td)!
        texture.label = label

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * cubeIndex.side
        let bytesPerImage = bytesPerRow * cubeIndex.side
        let region = MTLRegionMake2D(0, 0, cubeIndex.side, cubeIndex.side)

        addCubeFace(cubeIndex.left,  0)
        addCubeFace(cubeIndex.right, 1)
        addCubeFace(cubeIndex.top,   2)
        addCubeFace(cubeIndex.bot,   3)
        addCubeFace(cubeIndex.front, 4)
        addCubeFace(cubeIndex.back,  5)

        func addCubeFace(_ quad: Quad, _ slice: Int) {

            texture.replace(region        : region,
                            mipmapLevel   : 0,
                            slice         : slice,
                            withBytes     : quad,
                            bytesPerRow   : bytesPerRow,
                            bytesPerImage : bytesPerImage)
        }
        return texture
    }
    // for both metal and visionOS reflection
    override public func updateUniforms() {
        guard let eyebuf = cubeMesh.eyeBuf else { return }
        let drawableSize = pipeline.layer.drawableSize

        Task {
            let orientation = await Motion.shared.updateDeviceOrientation()

            let projection = project4x4(drawableSize)
            TimeLog(#function, interval: 4) {
                P("👁️ cubeNode") //\(orientation.digits(1))")
                //print("\t👁️c projection  ", projection.digits)
            }
            eyebuf.updateEyeUniforms(projection, orientation)
        }
    }

#if os(visionOS)

    /// Update projection and rotation
    override public func updateUniforms(_ drawable: LayerRenderer.Drawable,
                                        _ deviceAnchor: DeviceAnchor?) {
        
        let cameraPos = vector_float4([0, 0,  -4, 1])
        if #available(visionOS 2.0, *) {
            cubeMesh.eyeBuf?.updateEyeUniforms(drawable, deviceAnchor, cameraPos, "👁️C⃝ube")
        } else {
            // Fallback on earlier versions
        }
    }
    
#endif

}
