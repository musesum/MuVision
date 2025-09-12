// created by musesum on 9/7/25

#if os(visionOS)
import CompositorServices
#else
import Metal
import UIKit
#endif

extension CubeNode { // Make

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

}
