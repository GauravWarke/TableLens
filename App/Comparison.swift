import SwiftUI
import PhotosUI
import UIKit

@MainActor
func inspectionImage(_ source: UIImage) throws -> CGImage {
    guard source.size.width > 0, source.size.height > 0 else { throw LensError("Empty photo.") }
    let scale = min(1, 1024 / max(source.size.width, source.size.height))
    let size = CGSize(width: source.size.width*scale, height: source.size.height*scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
        source.draw(in: CGRect(origin: .zero, size: size))
    }
    guard let image = upright.cgImage else { throw LensError("Could not read the photo.") }
    return image
}

struct Capture: Codable {
    let jpeg: Data
    let items: [Detection]
    let date: Date

    init(image: UIImage, items: [Detection]) throws {
        guard let bytes = image.jpegData(compressionQuality: 0.86) else { throw LensError("Could not save the photo.") }
        jpeg = bytes
        self.items = items
        date = Date()
    }
    var counts: [String: Int] { Dictionary(grouping: items, by: \.name).mapValues { $0.count } }
}

private struct Pair: Codable {
    var before: Capture?
    var after: Capture?
    static func file() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true).appendingPathComponent("table-comparison-v1.json")
    }
}

struct Comparison: View {
    @ObservedObject var display: Display
    @Environment(\.dismiss) private var dismiss
    @State private var pair = Pair()
    @State private var selected: String?
    @State private var beforePhoto: PhotosPickerItem?
    @State private var afterPhoto: PhotosPickerItem?
    @State private var loadingBefore = false
    @State private var loadingAfter = false
    private var busy: Bool { loadingBefore || loadingAfter }
    @State private var status = "Photograph the same area from the same angle."
    @State private var clearing = false

    private var names: [String] {
        let a = pair.before?.counts ?? [:], b = pair.after?.counts ?? [:]
        return Set(a.keys).union(b.keys).sorted {
            let da = abs(a[$0,default:0]-b[$0,default:0])
            let db = abs(a[$1,default:0]-b[$1,default:0])
            return da == db ? $0 < $1 : da > db
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Before & after").font(.largeTitle)
                    Spacer()
                    Button("Done") { dismiss() }.disabled(busy)
                }
                Text(status)
                HStack(alignment: .top, spacing: 18) {
                    column(before: true)
                    column(before: false)
                }
                if pair.before != nil && pair.after != nil {
                    Text("Detected counts").font(.title2)
                    if names.isEmpty { Text("No supported objects detected in either image.") }
                    ForEach(names, id: \.self) { name in
                        let a = pair.before?.counts[name] ?? 0
                        let b = pair.after?.counts[name] ?? 0
                        Button {
                            selected = selected == name ? nil : name
                        } label: {
                            HStack {
                                Text(name.capitalized)
                                Spacer()
                                Text("\(a) → \(b)")
                                Text(a == b ? "Same count" : (b > a ? "\(b-a) more detected" : "\(a-b) fewer detected"))
                            }
                        }
                        .accessibilityHint("Highlight matching boxes in both photos")
                    }
                }
                if pair.before != nil || pair.after != nil { Button("Clear saved comparison", role: .destructive) { clearing = true }.disabled(busy) }
            }.padding(28)
        }.frame(minWidth: 780, minHeight: 540)
        .interactiveDismissDisabled(busy)
        .onAppear {
            do {
                let url = try Pair.file()
                if FileManager.default.fileExists(atPath: url.path) {
                    pair = try JSONDecoder().decode(Pair.self, from: Data(contentsOf: url))
                }
            } catch { status = error.localizedDescription }
        }
        .onChange(of: beforePhoto) { _, item in if let item { load(item, before: true) } }
        .onChange(of: afterPhoto) { _, item in if let item { load(item, before: false) } }
        .confirmationDialog("Delete both saved photos and their results?", isPresented: $clearing) {
            Button("Delete comparison", role: .destructive) {
                do { try FileManager.default.removeItem(at: Pair.file()); pair = Pair(); selected = nil; status = "Comparison cleared." }
                catch { status = error.localizedDescription }
            }
        }
    }

    private func column(before: Bool) -> some View {
        let capture = before ? pair.before : pair.after
        return VStack(alignment: .leading) {
            Text(before ? "Before" : "After").font(.headline)
            if let capture, let image = UIImage(data: capture.jpeg) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            ForEach(Array(capture.items.enumerated()), id: \.offset) { entry in
                                if selected == nil || selected == entry.element.name {
                                    let box = entry.element.box
                                    Rectangle().stroke(.yellow, lineWidth: 2)
                                        .frame(width:geo.size.width*box.width,height:geo.size.height*box.height)
                                        .position(x:geo.size.width*box.midX,y:geo.size.height*(1-box.midY))
                                }
                            }
                        }
                    }.frame(maxHeight: 225)
                Text(capture.date.formatted()).font(.caption)
            }
            if before ? loadingBefore : loadingAfter { ProgressView("Analysing photo…") }
            PhotosPicker(selection: before ? $beforePhoto : $afterPhoto, matching: .images) {
                Text(capture == nil ? "Choose photo" : "Choose retaken photo")
            }
            if display.frame != nil {
                Button("Use current scan") {
                    do {
                        guard let image = display.frame else { return }
                        try save(Capture(image: image, items: display.items), before: before)
                    } catch { status = error.localizedDescription }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        .disabled(before ? loadingBefore : loadingAfter)
    }

    private func save(_ capture: Capture, before: Bool) throws {
        var next = pair
        if before { next.before = capture } else { next.after = capture }
        try JSONEncoder().encode(next).write(to: Pair.file(), options: .atomic)
        pair = next
        selected = nil
        if next.before == nil { status = "After saved. Choose the Before photo." }
        else if next.after == nil { status = "Before saved. Choose the After photo." }
        else { status = "Select a category to inspect both photos." }
    }

    private func load(_ item: PhotosPickerItem, before: Bool) {
        if before {
            guard !loadingBefore else { return }
            loadingBefore = true
        } else {
            guard !loadingAfter else { return }
            loadingAfter = true
        }
        status = "Identifying objects…"
        Task { @MainActor in
            defer {
                if before { beforePhoto = nil; loadingBefore = false }
                else { afterPhoto = nil; loadingAfter = false }
            }
            do {
                guard let bytes = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: bytes) else { throw LensError("Could not open the selected photo.") }
                let cg = try inspectionImage(image)
                let detections = try await Detector.shared.analyze(cg)
                try save(Capture(image: UIImage(cgImage: cg), items: detections), before: before)
            } catch { status = error.localizedDescription }
        }
    }
}
