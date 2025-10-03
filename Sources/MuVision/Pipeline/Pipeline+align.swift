// created by musesum on 9/24/25

//  MetPipeline.swift
//  created by musesum on 3/13/23.

import Collections
import MetalKit
import Metal
import MuFlo
import MuHands
#if os(visionOS)
import CompositorServices
#endif

extension Pipeline {

    /// rotate textures to fit landscape/portrait aspect
    /// when user loads archive from other orientation
    public func alignNameTex(_ done: CallVoid? = nil) {
    
        for (name,tex) in archive.nameTex {
            guard let tex else { continue }

            if let (_,node,flo) = rotatable[name] {
                rotatable[name] = (tex,node,flo)
                flo.texture = aspectCopy(tex, type: .fit)
                flo.activate()
            } else {
                DebugLog { P("\(name) not found in rotatable") }
            }
        }
    }

    enum FillType { case fill, fit }
    func aspectCopy(_ sourceTex: MTLTexture, type: FillType) -> MTLTexture {
        if CGFloat(sourceTex.width)  == pipeSize.width,
           CGFloat(sourceTex.height) == pipeSize.height {
            return sourceTex
        }

        // Create destination texture with pipeline size
        guard let destTex = makeComputeTex(
            size: pipeSize,
            label: sourceTex.label ?? "resized",
            format: sourceTex.pixelFormat) else { return sourceTex }

        // Get source data
        guard let sourceData = sourceTex.rawData() else { return sourceTex }

        let srcWidth = sourceTex.width
        let srcHeight = sourceTex.height
        let dstWidth = Int(pipeSize.width)
        let dstHeight = Int(pipeSize.height)

        // Calculate aspect fill scale
        let scaleX = CGFloat(dstWidth) / CGFloat(srcWidth)
        let scaleY = CGFloat(dstHeight) / CGFloat(srcHeight)
        let scale = min(scaleX, scaleY)

        // Calculate sample region
        let sampleWidth = CGFloat(dstWidth) / scale
        let sampleHeight = CGFloat(dstHeight) / scale
        let offsetX = (CGFloat(srcWidth) - sampleWidth) / 2.0
        let offsetY = (CGFloat(srcHeight) - sampleHeight) / 2.0

        // Create destination buffer
        let dstBytesPerRow = dstWidth * 4
        var dstData = [UInt8](repeating: 0, count: dstWidth * dstHeight * 4)

        sourceData.withUnsafeBytes { srcPtr in
            let src32Ptr = srcPtr.bindMemory(to: UInt32.self)
            dstData.withUnsafeMutableBytes { dstPtr in
                let dst32Ptr = dstPtr.bindMemory(to: UInt32.self)

                for dy in 0 ..< dstHeight {
                    for dx in 0 ..< dstWidth {
                        let srcX = CGFloat(dx) * sampleWidth / CGFloat(dstWidth) + offsetX
                        let srcY = CGFloat(dy) * sampleHeight / CGFloat(dstHeight) + offsetY
                        let sx = Int(srcX)
                        let sy = Int(srcY)

                        if sx >= 0 && sx < srcWidth && sy >= 0 && sy < srcHeight {
                            let srcIndex = sy * srcWidth + sx
                            let dstIndex = dy * dstWidth + dx
                            dst32Ptr[dstIndex] = src32Ptr[srcIndex]
                        }
                    }
                }
            }
        }
        // Copy to texture
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: dstWidth, height: dstHeight, depth: 1))
        destTex.replace(region: region, mipmapLevel: 0, withBytes: dstData, bytesPerRow: dstBytesPerRow)

        return destTex
    }

    /// make new texture, or remake an old one if size changes.
    public func paletteTexture(_ node: PipeNode,
                               _ flo: Flo?,
                               rotate: Bool = true) {

        guard let flo else { return }
        let size = CGSize(width: 256, height: 1)

        let path = flo.path(3)
        if let tex = makeComputeTex(size: size,
                                    label: path,
                                    format: MuComputePixelFormat) {
            flo.texture = tex
            flo.reactivate()
            rotatable[path] = (tex, node, flo)
            DebugLog { P("🧭 paletteTexture\(size.digits(0)) \(path)") }
        }
    }

    private func makeComputeTex(size: CGSize,
                                label: String?,
                                format: MTLPixelFormat? = nil) -> MTLTexture? {
        let td = MTLTextureDescriptor()
        td.pixelFormat = MuComputePixelFormat
        td.width = Int(size.width)
        td.height = Int(size.height)
        td.usage = [.shaderRead, .shaderWrite]
        let tex = device.makeTexture(descriptor: td)
        if let label {
            tex?.label = label
        }
        return tex
    }
}
