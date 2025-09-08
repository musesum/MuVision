//  created by musesum on 4/2/23.

import Metal
import MuFlo

open class ComputeNode: PipeNode {

    var mtlCompute: MTLComputePipelineState? // _cellRulePipeline;
    var threadSize = MTLSize()
    var threadCount = MTLSize()

    override public init(_ pipeline : Pipeline,
                         _ pipeNode˚ : Flo) {

        super.init(pipeline, pipeNode˚)
    }


    open override func makeResources() {

        makeComputePipe()
        setupThreadGroup()

        func makeComputePipe() {

            if let shader,
               let kernelFunction = shader.kernelFunction,
               let device = MTLCreateSystemDefaultDevice() {
                do {
                    self.mtlCompute  = try device.makeComputePipelineState(function: kernelFunction)
                } catch{
                    PrintLog("⁉️ makeComputePipe: \(pipeFlo˚.name) failed error \(error)")
                }
            } else {
                PrintLog("⁉️ makeComputePipe: \(pipeFlo˚.name) failed")
            }
        }

    }
    func setupThreadGroup() {
        threadSize = MTLSizeMake(16, 16, 1)
        let width  = Int(pipeline.pipeSize.width)
        let height = Int(pipeline.pipeSize.height)
        threadCount.width  = (width  + 16 - 1) / 16
        threadCount.height = (height + 16 - 1) / 16
        threadCount.depth  = 1

        //TimeLog(#function, "threadgroup", interval: 4, log)
        func log() {
            print("\(pipeName) (\(width),\(height))")// thread size(\(threadSize.width),\(threadSize.height))  count(\(threadCount.width),\(threadCount.height)) remainder(\(drawW-threadSize.width*threadCount.width), \(drawH-threadSize.height*threadCount.height))")
        }
    }
    public func computeShader(_ computeEnc: MTLComputeCommandEncoder)  {
        if let mtlCompute {
            // execute the compute pipeline threads
            setupThreadGroup() 
            computeEnc.setComputePipelineState(mtlCompute)
            computeEnc.dispatchThreadgroups(threadCount, threadsPerThreadgroup: threadSize)
        }
    }
}
