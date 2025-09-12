// created by musesum on 9/12/25

import MuFlo
import Metal

#if false // deprecated

extension Pipeline {
    internal var rotateFunc: MTLFunction?
    /// rotate textures to fit landscape/portrait aspect
    /// when user loads archive from other orientation
    public func alignNameTex(_ done: CallVoid? = nil) {
        nextFrame.addBetweenFrame {
            Reset.reset()
        }
        return //.....
        for (name,tex) in archive.nameTex {
            guard let tex else { continue }

            if let newTex = rotateTexture(tex) {

                archive.nameTex[name] = newTex
                if let (_,node,flo) = rotatable[name] {
                    rotatable[name] = (newTex,node,flo)
                    flo.texture = aspectFill(newTex) ?? newTex
                    flo.activate()
                }
            } else if let (_,node,flo) = rotatable[name] {
                rotatable[name] = (tex,node,flo)
                flo.texture = aspectFill(tex) ?? tex
                flo.activate()
            } else {
                DebugLog { P("\(name) not found in rotatable") }
            }
        }
        activateRotateClosures(done)
    }

    public func activateRotateClosures(_ done: CallVoid?) {
        for closure in rotateClosure.values {
            closure()
        }
        DebugLog{ P("🚰 Pipeline:: \(#function)") }
        done?()
    }

    /// adjust textures between landscape/portrait
    /// usually when user rotates iphone
    public func rotateTextures(_ done: CallVoid? = nil) {

        guard layer.aspect != pipeSize.aspect else { return }
        pipeSize = pipeSize.withAspect(layer.aspect)

        for (name,(tex,node,flo)) in rotatable {
            if let newTex = rotateTexture(tex) {
                rotatable[name] = (newTex,node,flo)
                flo.texture = newTex
                flo.reactivate()
            }
        }
        activateRotateClosures(done)
    }

    @inline(__always)
    func rotateTexture(_ inTex: MTLTexture) -> MTLTexture? {

        guard inTex.aspect != layer.aspect else { return nil }
        guard let outTex = makeRotateTex() else { return nil }

        if rotateFunc == nil {
            rotateFunc = library?.makeFunction(name: "rotateTexture")
        }
        guard let rotateFunc,
              let pipeState = try? device.makeComputePipelineState(function: rotateFunc)
        else { PrintLog("Pipeline::\(#function) failed rotateFunc") ; return nil }

        // Set up a command buffer and encoder
        let commandBuf = commandQueue.makeCommandBuffer()!
        let computeEnc = commandBuf.makeComputeCommandEncoder()!
        computeEnc.setComputePipelineState(pipeState)

        // Bind in/out textures, with aspect buffer
        computeEnc.setTexture(inTex, index: 0)
        computeEnc.setTexture(outTex, index: 1)
        if let aspectBuf {
            computeEnc.setBuffer(aspectBuf, offset: 0, index: 0)
        }

        // Dispatch thread groups
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(width  : (inTex.width  + 15) / 16,
                                   height : (inTex.height + 15) / 16,
                                   depth  : 1)
        computeEnc.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)

        // End encoding and commit the command buffer
        computeEnc.endEncoding()
        commandBuf.commit()
        commandBuf.waitUntilCompleted()
        return outTex

        func makeRotateTex() -> MTLTexture? {
            let size = CGSize(width: inTex.height, height: inTex.width)
            if let tex = makeComputeTex(size: size,
                                        label: inTex.label,
                                        format: inTex.pixelFormat) {
                NoDebugLog { P("🧭 makeRotateTex for: \(tex.label ?? "??")") }
                return tex
            }
            return nil
        }
    }
    func aspectFill(_ sourceTex: MTLTexture) -> MTLTexture? {

        if CGFloat(sourceTex.width)   == pipeSize.width,
           CGFloat(sourceTex.height) == pipeSize.height {
            return sourceTex
        }

        // Create destination texture with pipeline size
        guard let destTex = makeComputeTex(
            size: pipeSize,
            label: sourceTex.label ?? "resized",
            format: sourceTex.pixelFormat) else { return nil }

        // Get source data
        guard let sourceData = sourceTex.rawData() else { return nil }

        let srcWidth = sourceTex.width
        let srcHeight = sourceTex.height
        let dstWidth = Int(pipeSize.width)
        let dstHeight = Int(pipeSize.height)

        // Calculate aspect fill scale
        let scaleX = CGFloat(dstWidth) / CGFloat(srcWidth)
        let scaleY = CGFloat(dstHeight) / CGFloat(srcHeight)
        let scale = max(scaleX, scaleY)

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
#endif
