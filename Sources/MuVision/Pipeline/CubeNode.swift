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

public class CubeNode: RenderNode {

    private let viaIndex   : Bool
    private var cubeMesh   : CubeMesh!
    private var cubeIndex  : CubemapIndex?
    private var inTex˚     : Flo?
    private var cudex˚     : Flo?
    private var mixcube˚   : Flo?
    private var lastAspect : Aspect?

    override public init(_ pipeline : Pipeline,
                         _ pipeNode˚ : Flo) {

        self.cubeMesh = CubeMesh(pipeline.renderState)
        self.viaIndex = true
        super.init(pipeline, pipeNode˚)
        
        inTex˚ = pipeNode˚.superBindPath("in")
        cudex˚ = pipeNode˚.superBindPath("cudex")
        mixcube˚ = pipeNode˚.superBindPath("mixcube")
        makeRenderPipeline()
        makeResources()
        pipeline.rotateClosure["cudex˚"] = { self.remakeAspect() }
    }
    
    func makeRenderPipeline() {
        shader = Shader(pipeline,
                        file: "render.map.cube",
                        vertex: "cubeVertex",
                        fragment: "cubeIndexFragment")
        renderPipelineState = makeRenderState(cubeMesh.metalVD)
    }

    func remakeAspect() {
        if let lastAspect, lastAspect == pipeline.pipeSize.aspect { return }
        self.lastAspect = pipeline.pipeSize.aspect
        pipeline.customTexture(cudex˚, makeCube, remake: true)
    }
    override open func makeResources() {

        remakeAspect()
        cubeMesh.eyeBuf = EyeBuf("CubeEyes", far: false)
        super.makeResources()
    }
    func makeCube() -> MTLTexture? {
        if viaIndex {
            let label = cudex˚?.path(3) ?? "cudex"
            return  makeIndexCube(pipeline.pipeSize, label)
        } else {
            let facenames = ["front", "front", "top", "bottom", "front", "front"]
            return makeImageCube(facenames)
        }
    }

    override open func renderNode(_ renderEnc: MTLRenderCommandEncoder,
                                  _ renderState: RenderState) {
        guard let renderPipelineState else { return }

        cubeMesh.eyeBuf?.setUniformBuf(renderEnc)
        mixcube˚?.updateMtlBuffer()

        renderEnc.setFragmentTexture(inTex˚, index: 0)
        renderEnc.setFragmentTexture(cudex˚, index: 1)
        renderEnc.setFragmentBuffer (mixcube˚, index: 0)

        renderEnc.setRenderPipelineState(renderPipelineState)
        cubeMesh.drawMesh(renderEnc, renderState)
        cudex˚?.activate(from: cudex˚)
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

        let orientation = Motion.shared.updateDeviceOrientation()
        let projection = project4x4(pipeline.layer.drawableSize)

        NoTimeLog(#function, interval: 4) {
            print("\t👁️c orientation ", orientation.digits)
            print("\t👁️c projection  ", projection.digits)
        }
        cubeMesh.eyeBuf?.updateEyeUniforms(projection, orientation)
    }
#if os(visionOS)

    /// Update projection and rotation
    override public func updateUniforms(_ drawable: LayerRenderer.Drawable,
                                        _ deviceAnchor: DeviceAnchor?) {
        let cameraPos =  vector_float4([0, 0,  -4, 1]) //????
        cubeMesh.eyeBuf?.updateEyeUniforms(drawable, deviceAnchor, cameraPos, "👁️C⃝ube")
    }
    
#endif

}
