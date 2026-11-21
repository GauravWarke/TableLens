import SwiftUI
import RealityKit
import ARKit
import Vision
import CoreML
import PhotosUI
import UIKit
import CoreImage
import AVFoundation
import UniformTypeIdentifiers

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
    let pack = PackSession()
    @Published var frame: UIImage?
    @Published var items: [Detection] = []
    @Published var status = "Choose a scan mode."
    func show(_ image: CGImage, _ results: [Detection], live: Bool = false) {
        let photo = UIImage(cgImage: image)
        frame = photo
        pack.observe(photo, items: results, live: live)
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
        ImmersiveSpace(id: "camera") { CameraSpace(display: display) }
    }
}

struct Home: View {
    @ObservedObject var display: Display
    @Environment(\.openImmersiveSpace) var open
    @Environment(\.dismissImmersiveSpace) var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var running = false
    @State private var comparing = false
    @State private var packing = false
    @State private var liveFallback = false
    var body: some View {
        VStack(spacing: 16) {
            Text("TableLens").font(.largeTitle)
            HStack {
                Button("Compare before & after") { comparing = true }
                PhotosPicker("Identify from photo", selection: $photo, matching: .images)
                    .disabled(running || liveFallback)
                Button("Live object detection") { startLive() }.disabled(running || liveFallback)
                Button("Track reference objects") { start("references") }.disabled(running || liveFallback)
                if running || liveFallback {
                    Button("Stop") {
                        Task {
                            if running { await dismiss(); running = false }
                            liveFallback = false
                            display.status = "Stopped."
                        }
                    }
                }
            }
            Picker("Workflow", selection: $packing) {
                Text("Identify objects").tag(false)
                Text("Find & pack up").tag(true)
            }.pickerStyle(.segmented)
            if packing { PackPanel(session: display.pack) }
            else { Inventory(display: display) }
        }.padding(32)
        .sheet(isPresented: $comparing) { Comparison(display: display) }
        .sheet(isPresented: $liveFallback) {
            LiveFallbackScan(display: display) {
                liveFallback = false
                display.pack.endInput()
                display.status = "Stopped."
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("TableLensSpaceClosed"))) { _ in running = false; display.pack.endInput() }
        .task(id: photo) {
            guard let photo else { return }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self),
                      let ui = UIImage(data: data) else { throw LensError("Could not decode photo.") }
                let cg = try inspectionImage(ui)
                let items = try await Detector.shared.analyze(cg)
                if !Task.isCancelled && !running && !liveFallback { display.show(cg,items) }
            } catch { if !Task.isCancelled { display.status = error.localizedDescription } }
        }
    }

    func startLive() {
        display.pack.endInput()
        display.frame = nil
        display.items = []
        if CameraFrameProvider.isSupported {
            start("camera")
        } else {
            liveFallback = true
            display.status = "Headset camera unavailable here. Pick a video or photo for continuous detection."
        }
    }

    func start(_ id: String) {
        running = true
        display.pack.endInput()
        display.frame = nil; display.items = []; display.status = "Opening…"
        Task {
            switch await open(id: id) {
            case .opened: break
            default: running = false; display.status = "Space did not open."
            }
        }
    }
}

/// Continuous YOLO on a user-chosen video/photo when main-camera access is unavailable (Simulator / no entitlement).
struct LiveFallbackScan: View {
    @ObservedObject var display: Display
    var onStop: () -> Void
    @State private var media: PhotosPickerItem?
    @State private var task: Task<Void, Never>?
    @State private var looping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Live object detection").font(.largeTitle)
                Spacer()
                Button("Done") { stop(); onStop() }
            }
            Text(display.status)
            PhotosPicker(
                "Choose video or photo",
                selection: $media,
                matching: .any(of: [.videos, .images])
            )
            .disabled(task != nil && !looping)
            if task != nil {
                Button(looping ? "Pause loop" : "Resume loop") {
                    looping.toggle()
                }
            }
            Inventory(display: display)
            Text("On Vision Pro with Main Camera Access, use Live object detection for the real headset feed. This fallback streams frames from a video or repeats a still photo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .onChange(of: media) { _, item in
            guard let item else { return }
            start(item)
        }
        .onDisappear { stop() }
    }

    func stop() {
        task?.cancel()
        task = nil
        looping = false
    }

    func start(_ item: PhotosPickerItem) {
        stop()
        looping = true
        display.status = "Loading media…"
        task = Task {
            do {
                if let movie = try await item.loadTransferable(type: VideoFile.self) {
                    try await streamVideo(movie.url)
                } else if let data = try await item.loadTransferable(type: Data.self),
                          let ui = UIImage(data: data) {
                    let cg = try inspectionImage(ui)
                    try await streamStill(cg)
                } else {
                    throw LensError("Could not read that media.")
                }
            } catch is CancellationError {
                // stopped
            } catch {
                if !Task.isCancelled { display.status = error.localizedDescription }
            }
        }
    }

    @MainActor
    func streamStill(_ image: CGImage) async throws {
        display.status = "Live loop on still frame. Pause or Done to stop."
        while !Task.isCancelled {
            if looping {
                let items = try await Detector.shared.analyze(image)
                if !Task.isCancelled { display.show(image, items) }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    @MainActor
    func streamVideo(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        let duration = try await asset.load(.duration)
        let step = CMTime(seconds: 0.5, preferredTimescale: 600)
        display.status = "Live detection from video…"
        while !Task.isCancelled {
            var time = CMTime.zero
            while !Task.isCancelled, time <= duration {
                if looping {
                    let cg = try await image(at: time, generator: generator)
                    let items = try await Detector.shared.analyze(cg)
                    if !Task.isCancelled { display.show(cg, items) }
                    try await Task.sleep(nanoseconds: 500_000_000)
                } else {
                    try await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                time = CMTimeAdd(time, step)
            }
        }
    }

    func image(at time: CMTime, generator: AVAssetImageGenerator) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { cgImage, _, error in
                if let cgImage {
                    continuation.resume(returning: cgImage)
                } else {
                    continuation.resume(throwing: error ?? LensError("Could not read a video frame."))
                }
            }
        }
    }
}

struct VideoFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("tablelens-live-\(UUID().uuidString)")
                .appendingPathExtension(received.file.pathExtension)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoFile(url: dest)
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
            guard !urls.isEmpty else {
                throw LensError("Reference tracking needs trained .referenceobject files in Resources. For everyday items, choose Stop, then Live object detection.")
            }
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
                throw LensError("No supported main-camera format. Use Live object detection fallback with a video, or install a Main Camera Access build.")
            }
            let provider = CameraFrameProvider()
            let permission = await session.requestAuthorization(for:[.cameraAccess])
            guard permission[.cameraAccess] == .allowed else { throw LensError("Main-camera permission was denied.") }
            try await session.run([provider])
            guard let frames = provider.cameraFrameUpdates(for:format) else {
                throw LensError("Main camera unavailable. Check entitlement and enterprise license.")
            }
            let context = CIContext()
            var previous = Date.distantPast
            display.status = "Live detection. Look at the table…"
            for await frame in frames {
                if Task.isCancelled { break }
                guard Date().timeIntervalSince(previous) >= 0.5, let sample = frame.sample(for:.left) else { continue }
                previous = Date()
                let original = CIImage(cvPixelBuffer:sample.pixelBuffer)
                let scale = min(1, 960/max(original.extent.width,original.extent.height))
                let small = original.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
                guard let image = context.createCGImage(small,from:small.extent) else { continue }
                let items = try await Detector.shared.analyze(image)
                if !Task.isCancelled { display.show(image,items,live: true) }
            }
        } catch { display.status = error.localizedDescription }
    }
}
