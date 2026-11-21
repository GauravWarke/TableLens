import SwiftUI
import UIKit

struct Sighting {
    let image: UIImage
    let matches: [Detection]
    let scanned: Date
    let live: Bool
}

@MainActor
final class PackSession: ObservableObject {
    @Published private(set) var checklist = ["cell phone", "mouse", "book"]
    @Published private(set) var packed: Set<String> = []
    @Published private(set) var history: [String: Sighting] = [:]
    @Published private(set) var latest: Set<String> = []
    private var previous: Set<String> = []
    private var previousTime: Date?

    func observe(_ image: UIImage, items: [Detection], live: Bool) {
        let now = Date()
        let groups = Dictionary(grouping: items, by: \.name)
        let names = Set(groups.keys)
        let consecutive = previousTime.map { now.timeIntervalSince($0) <= 3 } ?? false
        let confirmed = live ? (consecutive ? names.intersection(previous) : []) : names
        previous = live ? names : []
        previousTime = live ? now : nil
        latest = confirmed
        for name in confirmed {
            history[name] = Sighting(image: image, matches: groups[name] ?? [], scanned: now, live: live)
        }
    }
    func endInput() { latest = []; previous = []; previousTime = nil }
    func add(_ name: String) {
        if !checklist.contains(name) { checklist.append(name) }
    }
    func togglePacked(_ name: String) {
        if packed.contains(name) { packed.remove(name) } else { packed.insert(name) }
    }
    func remove(_ name: String) { checklist.removeAll { $0 == name }; packed.remove(name) }
    func reset() { endInput(); checklist = []; packed = []; history = [:] }
    func current(_ name: String, at date: Date) -> Bool {
        guard latest.contains(name), let sight = history[name] else { return false }
        return !sight.live || date.timeIntervalSince(sight.scanned) < 3
    }
}

struct PackPanel: View {
    @ObservedObject var session: PackSession
    @State private var query = ""
    @State private var target = ""
    @State private var reset = false
    private let common = ["cell phone","mouse","book","laptop","keyboard","remote","cup","bottle","backpack","handbag","scissors","umbrella"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Find an item, e.g. phone", text: $query)
                    Menu("Choose item") {
                        ForEach(Array(Set(common + Array(session.history.keys) + session.checklist)).sorted(), id: \.self) { name in
                            Button(name) { query = name; target = name }
                        }
                    }
                    Button("Find") { target = term }.disabled(term.isEmpty)
                }
                if !target.isEmpty {
                    HStack {
                        Text(target.capitalized).font(.title2)
                        if !session.checklist.contains(target) {
                            Button("Add to checklist") { session.add(target) }
                        }
                    }
                    if let sight = session.history[target] {
                        TimelineView(.periodic(from: .now, by: 1)) { clock in
                            Text(session.current(target, at: clock.date) ? (sight.live ? "Visible in latest live scan" : "Visible in latest photo") : "Last sighting")
                        }
                        Text("Scan time " + sight.scanned.formatted(date: .omitted, time: .standard))
                        if sight.matches.count > 1 { Text("\(sight.matches.count) candidates. Check the highlighted objects to identify yours.") }
                        Image(uiImage: sight.image).resizable().aspectRatio(contentMode: .fit)
                            .overlay {
                                GeometryReader { geo in
                                    ForEach(Array(sight.matches.enumerated()), id: \.offset) { entry in
                                        let box = entry.element.box
                                        Rectangle().stroke(.yellow, lineWidth: 3)
                                            .frame(width: geo.size.width*box.width, height: geo.size.height*box.height)
                                            .position(x: geo.size.width*box.midX, y: geo.size.height*(1-box.midY))
                                    }
                                }
                            }.frame(maxHeight: 210)
                    } else { Text("No recorded sighting this session. Scan the table or choose another photo.") }
                }
                Text("Pack-up checklist").font(.headline)
                Text("\(session.packed.count) of \(session.checklist.count) marked packed")
                TimelineView(.periodic(from: .now, by: 1)) { clock in
                    VStack(alignment: .leading) {
                        ForEach(session.checklist, id: \.self) { name in
                            HStack {
                                Button(name.capitalized) { target = name; query = name }
                                if session.packed.contains(name) { Text("Packed by you") }
                                else if session.current(name, at: clock.date) { Text("Seen in latest scan") }
                                else { Text("Unconfirmed") }
                                Spacer()
                                Button(session.packed.contains(name) ? "Undo packed" : "Mark packed") { session.togglePacked(name) }
                                Button { session.remove(name) } label: { Image(systemName: "minus.circle") }
                                    .accessibilityLabel("Remove " + name + " from checklist")
                            }
                        }
                    }
                }
                Button("Start empty session") { reset = true }
                    .confirmationDialog("Clear this checklist and all session sightings?", isPresented: $reset) {
                        Button("Clear and start", role: .destructive) { session.reset(); target = ""; query = "" }
                    }
            }
        }
    }
    private var term: String {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["phone":"cell phone","mobile":"cell phone","mobile phone":"cell phone"].first { $0.key == text }?.value ?? text
    }
}
