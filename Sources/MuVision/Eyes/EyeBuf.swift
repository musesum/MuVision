// created by musesum

import MetalKit

/// triple buffered Uniform for either 1 or 2 eyes
open class EyeBuf {

    public struct UniEyes {
        var eye: (UniformEye, UniformEye) // a uniform for each eye
    }
    let eyeSize: Int
    let eye3Size: Int // triple buffer
    let infinitelyFar: Bool // infinit distance for stars (same background for both eyes)
    let eyeBuf: MTLBuffer
    var eyes: UnsafeMutablePointer<UniEyes>!
    var tripleOffset = 0
    var tripleIndex = 0
    var rotation: Float = 0

    public init?(_ label: String, far: Bool) {
        // round up to multiple of 256 bytes
        self.eyeSize = (MemoryLayout<UniEyes>.size + 0xFF) & -0x100
        self.eye3Size = eyeSize * 3 // triple buffer
        self.infinitelyFar = far
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.eyeBuf = device.makeBuffer(length: eye3Size, options: [.storageModeShared])!
        self.eyeBuf.label = label
        nextTripleUniformBuffer()
    }

    /// Update projection and rotation
    public func updateEyeUniforms(_ projection: matrix_float4x4,
                                  _ viewModel: matrix_float4x4) {
        nextTripleUniformBuffer()
        self.eyes[0].eye.0 = UniformEye(projection, viewModel)
    }

    func nextTripleUniformBuffer() {

        tripleIndex = (tripleIndex + 1) % 3 // triple buffer
        tripleOffset = eyeSize * tripleIndex
        let eyePtr = eyeBuf.contents() + tripleOffset
        eyes = UnsafeMutableRawPointer(eyePtr)
            .bindMemory(to: UniEyes.self, capacity: 1)
    }

    public func setUniformBuf(_ renderEnc: MTLRenderCommandEncoder)  {

        renderEnc.setVertexBuffer(eyeBuf, offset: tripleOffset, index: 15)

    }

}
