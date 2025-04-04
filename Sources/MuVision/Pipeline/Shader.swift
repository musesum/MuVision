// created by musesum on 6/11/24
import Metal
import MetalKit
import QuartzCore
import MuFlo

@MainActor //_____
public class Shader {

    var pipeline: Pipeline
    var fileName: String?
    var kernelName: String?
    var vertexName: String?
    var fragmentName: String?

    public var vertexFunction: MTLFunction?
    public var kernelFunction: MTLFunction?
    public var fragmentFunction: MTLFunction?

    public var runtimeLibrary: MTLLibrary?
    public var function: MTLFunction?

    public init(_ pipeline: Pipeline,
                file: String? = nil,
                kernel: String? = nil,
                vertex: String? = nil,
                fragment: String? = nil) {

        self.pipeline = pipeline
        self.kernelName = kernel
        self.vertexName = vertex
        self.fragmentName = fragment

        makeLibrary()
        makeFunctions()
    }

    public func makeLibrary() {

        if (missingFunction(kernelName) ||
            missingFunction(vertexName) ||
            missingFunction(fragmentName)) {

            makeNewLibrary()

        } else {
            self.runtimeLibrary = pipeline.library
        }

        func missingFunction(_ name: String?) -> Bool {
            if let name,
                let library = pipeline.library,
               library.functionNames.contains(name) == false {
                
                return true
            }
            return false
        }

        func makeNewLibrary() {
            if let fileName,
               let data = MuVision.read(fileName, "metal") {
                
                do {
                    print("makeLibrary: \(String(describing: fileName))")
                    runtimeLibrary = try pipeline.device.makeLibrary(source: data, options: MTLCompileOptions())
                }
                catch {
                    err("makeLibrary: err \(error)")
                }
            }
            func err(_ msg: String) {
                PrintLog("⁉️ ShaderFunc::makeNewLibrary \(msg)") }
        }
    }
    func makeFunctions() {
        kernelFunction = makeFunction(kernelName)
        vertexFunction = makeFunction(vertexName)
        fragmentFunction = makeFunction(fragmentName)

        func makeFunction(_ name: String?) -> MTLFunction? {
            if let name,
               let runtimeLibrary,
                let fn = (runtimeLibrary.makeFunction(name: name) ??
                          pipeline.library?.makeFunction(name:name) ?? nil) {
                return fn
            }
            return nil
        }
    }
}
