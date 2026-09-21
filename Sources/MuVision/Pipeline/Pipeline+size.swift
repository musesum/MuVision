// created by musesum on 9/9/26

import Metal
import MuFlo

extension Pipeline {

    /// remake every pipe texture as a 2^exp2 square; unchanged size is a no-op
    public func setPipeSize(exp2: Int) {
        let side = CGFloat(1 << max(4, min(exp2, 12)))
        let newSize = CGSize(width: side, height: side)
        guard newSize != pipeSize else { return }
        let wasRunning = pipeRunning
        pipeRunning = false
        pipeSize = newSize
        for (_, flo) in rotatable {
            if let tex = flo.texture {
                flo.texture = aspectCopy(tex)
                flo.activate()
            }
        }
        resizeFrame(layer.frame, layer.drawableSize, layer.contentsScale, true)
        pipeRunning = wasRunning
        DebugLog { P("🚰 setPipeSize \(newSize.digits(0))") }
    }
}
