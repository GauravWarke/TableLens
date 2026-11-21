import SwiftUI
import RealityKit
import ARKit
import Vision
import CoreML
import PhotosUI
import UIKit
import CoreImage

struct Detection: Codable {
    let name: String
    let score: Float
    let box: CGRect
}

actor Detector {
    static let shared = Detector()
    private var model: VNCoreMLModel?

    func analyze(_ image: CGImage) throws -> [Detection] {
        if model == nil {
            guard let url = Bundle.main.url(forResource: "TableObjects", withExtension: "mlmodelc") else {
                throw LensError("Missing detector. Run Prepare.command on the Mac.")
            }
            model = try VNCoreMLModel(for: MLModel(contentsOf: url))
        }
        guard let model else { throw LensError("Could not load the detector.") }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            throw LensError("Unexpected model output.")
        }
        return results.compactMap { object in
            guard let label = object.labels.first, label.confidence >= 0.45,
                  label.identifier != "dining table" else { return nil }
            return Detection(name: label.identifier, score: label.confidence, box: object.boundingBox)
        }
    }
}

struct LensError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
final class Display: ObservableObject {
    @Published var frame: UIImage?
    @Published var items: [Detection] = []
    @Published var status = "Choose a scan mode."
    func show(_ image: CGImage, _ results: [Detection]) {
        frame = UIImage(cgImage: image)
        items = results
        status = results.isEmpty ? "No supported objects detected." : "Detected \(results.count) objects."
    }
}

struct Inventory: View {
    @ObservedObject var display: Display
    var body: some View {
        VStack {
            if let frame = display.frame {
                Image(uiImage: frame).resizable().aspectRatio(contentMode: .fit)
                    .overlay {
                        GeometryReader { proxy in
                            ForEach(Array(display.items.enumerated()), id: \.offset) { entry in
                                let item = entry.element
                                let rect = item.box
                                let w = proxy.size.width, h = proxy.size.height
                                ZStack(alignment: .topLeading) {
                                    Rectangle().stroke(.yellow, lineWidth: 2)
                                    Text(item.name).font(.caption).padding(2).background(.black)
                                }
                                .frame(width: rect.width*w,height: rect.height*h)
                                .position(x:rect.midX*w, y:(1-rect.midY)*h)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
            }
            Text(display.status)
            let groups = Dictionary(grouping: display.items, by: \.name)
            Text(groups.keys.sorted().map { "\($0) × \(groups[$0]?.count ?? 0)" }.joined(separator: " · "))
        }
    }
}

@main
struct TableLensApp: App {
    @StateObject var display = Display()
    var body: some SwiftUI.Scene {
        WindowGroup { Home(display: display) }
        ImmersiveSpace(id: "references") { ReferenceSpace(display: display) }
        #if LIVE_CAMERA
        ImmersiveSpace(id: "camera") { CameraSpace(display: display) }
        #endif
    }
}

struct Home: View {
    @ObservedObject var display: Display
    @Environment(\.openImmersiveSpace) var open
    @Environment(\.dismissImmersiveSpace) var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var running = false
    @State private var comparing = false
    var body: some View {
        VStack(spacing: 16) {
            Text("TableLens").font(.largeTitle)
            HStack {
                Button("Compare before & after") { comparing = true }
                PhotosPicker("Identify from photo", selection: $photo, matching: .images)
                    .disabled(running)
                Button("Track reference objects") { start("references") }.disabled(running)
                #if LIVE_CAMERA
                Button("Scan through headset") { start("camera") }.disabled(running)
                #endif
                if running {
                    Button("Stop") { Task { await dismiss(); running = false; display.status = "Stopped." } }
                }
            }
            Inventory(display: display)
        }.padding(32)
        .sheet(isPresented: $comparing) { Comparison(display: display) }
        .onReceive(NotificationCenter.default.publisher(for: .init("TableLensSpaceClosed"))) { _ in running = false }
        .task(id: photo) {
            guard let photo else { return }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self),
                      let ui = UIImage(data: data) else { throw LensError("Could not decode photo.") }
                let cg = try inspectionImage(ui)
                let items = try await Detector.shared.analyze(cg)
                if !Task.isCancelled && !running { display.show(cg,items) }
            } catch { if !Task.isCancelled { display.status = error.localizedDescription } }
        }
    }
    func start(_ id: String) {
        running = true
        display.frame = nil; display.items = []; display.status = "Opening…"
        Task {
            switch await open(id: id) {
            case .opened: break
            default: running = false; display.status = "Space did not open."
            }
        }
    }
}

struct ReferenceSpace: View {
    @ObservedObject var display: Display
    @State private var root = Entity()
    @State private var session = ARKitSession()
    var body: some View {
        RealityView { content in content.add(root) }
            .task { await track() }
            .onDisappear { session.stop(); NotificationCenter.default.post(name:.init("TableLensSpaceClosed"),object:nil) }
    }
    @MainActor func track() async {
        do {
            let urls = Bundle.main.urls(forResourcesWithExtension:"referenceobject",subdirectory:nil) ?? []
            guard !urls.isEmpty else { throw LensError("Add trained .referenceobject files to Resources on the Mac, then rebuild. Choose Stop to exit.") }
            guard ObjectTrackingProvider.isSupported else { throw LensError("Object tracking requires a supported headset.") }
            var references: [ReferenceObject] = []
            for url in urls { references.append(try await ReferenceObject(from:url)) }
            let provider = ObjectTrackingProvider(referenceObjects: references)
            try await session.run([provider])
            display.status = "Look around the table for an enrolled object."
            var anchors: [UUID:Entity] = [:]
            for await update in provider.anchorUpdates {
                if Task.isCancelled { break }
                let anchor = update.anchor
                if update.event == .removed || !anchor.isTracked {
                    anchors.removeValue(forKey:anchor.id)?.removeFromParent()
                } else {
                    let node: Entity
                    if let existing = anchors[anchor.id] { node = existing }
                    else {
                        node = Entity()
                        let mesh = MeshResource.generateText(anchor.referenceObject.name, extrusionDepth:0.0005,font:.systemFont(ofSize:0.022))
                        let tag = ModelEntity(mesh:mesh,materials:[UnlitMaterial(color:.yellow)])
                        tag.components.set(BillboardComponent())
                        tag.position.y = 0.04
                        node.addChild(tag); root.addChild(node); anchors[anchor.id] = node
                    }
                    node.transform = Transform(matrix:anchor.originFromAnchorTransform)
                }
                display.status = "Tracking \(anchors.count) enrolled objects."
            }
        } catch { display.status = error.localizedDescription }
    }
}

#if LIVE_CAMERA
struct CameraSpace: View {
    @ObservedObject var display: Display
    @State private var session = ARKitSession()
    var body: some View {
        RealityView { _ in }
            .task { await capture() }
            .onDisappear { session.stop(); NotificationCenter.default.post(name:.init("TableLensSpaceClosed"),object:nil) }
    }
    @MainActor func capture() async {
        do {
            guard CameraFrameProvider.isSupported,
                  let format = CameraVideoFormat.supportedVideoFormats(for:.main,cameraPositions:[.left]).first else {
                throw LensError("No supported main-camera format on this device.")
            }
            let provider = CameraFrameProvider()
            let permission = await session.requestAuthorization(for:[.cameraAccess])
            guard permission[.cameraAccess] == .allowed else { throw LensError("Main-camera permission was denied.") }
            try await session.run([provider])
            guard let frames = provider.cameraFrameUpdates(for:format) else { throw LensError("Main camera unavailable. Check entitlement and license.") }
            let context = CIContext()
            var previous = Date.distantPast
            display.status = "Look at the table. Scanning…"
            for await frame in frames {
                if Task.isCancelled { break }
                guard Date().timeIntervalSince(previous) >= 0.5, let sample = frame.sample(for:.left) else { continue }
                previous = Date()
                let original = CIImage(cvPixelBuffer:sample.pixelBuffer)
                let scale = min(1, 960/max(original.extent.width,original.extent.height))
                let small = original.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
                guard let image = context.createCGImage(small,from:small.extent) else { continue }
                let items = try await Detector.shared.analyze(image)
                if !Task.isCancelled { display.show(image,items) }
            }
        } catch { display.status = error.localizedDescription }
    }
}
#endif
