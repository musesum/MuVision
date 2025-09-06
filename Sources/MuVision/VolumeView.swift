#if os(visionOS)
import RealityKit
import SwiftUI
import UIKit
import MuFlo

@MainActor
public struct VolumeView: View {

    final class ViewModel: ObservableObject {
        @Published var drawQueue: [TextureResource.DrawableQueue] = []
        @Published var faceTex: [TextureResource] = []
    }

    let pipeline: Pipeline
    var _cubeNode: CubeNode?
    var cubeNode: CubeNode? {
        guard let _cubeNode = _cubeNode ?? pipeline.node["cube"] as? CubeNode else { return nil }
        return _cubeNode
    }

    @StateObject private var vm = ViewModel()

    public init(_ pipeline: Pipeline) {
        self.pipeline = pipeline
    }

    // Build 6 materials backed by live DrawableQueues; fall back to solid tints if anything fails.
    private func makeMaterials(side: Int) async -> [RealityKit.Material] {
        do {
            let descriptor = TextureResource.DrawableQueue.Descriptor(
                pixelFormat: .bgra8Unorm,
                width: side,
                height: side,
                usage: [.renderTarget, .shaderRead],
                mipmapsMode: .none
            )

            // Create six queues (one per face) — synchronous
            let queues: [TextureResource.DrawableQueue] = try (0..<6).map { _ in try TextureResource.DrawableQueue(descriptor) }

            // Publish queues to the stable ViewModel immediately
            vm.drawQueue = queues
            PrintLog("✅ makeMaterials: published \(queues.count) draw queues")

            // Create six in-memory textures and immediately back them with the queues (no asset load)
            var textures: [TextureResource] = []
            for i in 0..<6 {
                let cgImg = make1x1CGImage(UInt8(i))
                let tex = try await TextureResource(image: cgImg, options: .init(semantic: .color))
                tex.replace(withDrawables: queues[i])
                textures.append(tex)
            }

            vm.faceTex = textures
            PrintLog("✅ makeMaterials: faceTex.count=\(textures.count)")

            // Textured UnlitMaterial
            return textures.map {
                var m = UnlitMaterial()
                m.color = .init(texture: .init($0))
                return m
            }
        } catch {
            // Log and fallback: solid-color UnlitMaterial so RealityView always has a 3D entity
            PrintLog("⁉️ VolumeView.makeMaterials error: \(error)")
            vm.drawQueue = []
            vm.faceTex = []
            let tints: [UIColor] = [.red, .green, .blue, .yellow, .cyan, .orange]
            return tints.map { tint in
                var m = UnlitMaterial()
                m.color = .init(tint: tint)
                return m
            }
        }
    }

    // temp 1×1 CGImage
    private func make1x1CGImage(_ face: UInt8) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0] // transparent
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * 1
        let bitsPerComponent = 8

        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = ctx.makeImage() else {
            // As a last resort, create a 1×1 opaque black pixel
            var fallbackPixel: [UInt8] = [0, 0, 0, 255]
            let fallbackCtx = CGContext(
                data: &fallbackPixel,
                width: 1,
                height: 1,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            return fallbackCtx!.makeImage()!
        }
        return image
    }

    private func addCube(_ content: RealityViewContent) async {
        let side = 512
        let materials = await makeMaterials(side: side)
        let mesh = MeshResource.generateBox(width: 0.25,
                                            height: 0.25,
                                            depth: 0.25,
                                            splitFaces: true)
        let model = ModelEntity(mesh: mesh, materials: materials)
        content.add(model)
    }

    public var body: some View {
        RealityView { content in
            await addCube(content)
        } update: { _ in
            let count = vm.drawQueue.count
            if count == 6 {
                cubeNode?.bakeFacesMRT(to: vm.drawQueue)
            }
        }
    }
}
#endif
