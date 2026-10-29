import SwiftUI
import AppKit
import NoteToIssueCore

struct EntryDetailView: View {
    @ObservedObject var model: AppModel
    let entry: Entry
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    StatusBadge(status: entry.status)
                    Spacer()
                    if let draft = entry.draft { Text("Confiance \(Int(draft.confidence * 100)) %").font(.caption).foregroundStyle(.secondary) }
                }
                Text(entry.draft?.isIssue == true ? entry.draft!.title : entry.note.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded)).textSelection(.enabled)
                Label(entry.repository, systemImage: "arrow.triangle.branch").font(.callout.monospaced()).foregroundStyle(.secondary)
                if let draft = entry.draft, !draft.labels.isEmpty {
                    HStack { ForEach(draft.labels, id: \.self) { label in
                        Text(label).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 5).background(.blue.opacity(0.10), in: Capsule())
                    } }
                }
                if let draft = entry.draft, draft.isIssue {
                    Divider()
                    Text("ISSUE PROPOSÉE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(LocalizedStringKey(draft.body)).font(.body).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !entry.message.isEmpty {
                    Label(entry.message, systemImage: entry.status == .uncertain ? "exclamationmark.triangle" : "sparkles")
                        .font(.callout).foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                }
                HStack {
                    if let url = entry.issueURL { Link("Ouvrir l'issue GitHub ↗", destination: url).buttonStyle(.borderedProminent) }
                    if entry.status == .review {
                        Button("Publier cette proposition") { Task { await model.publish(entry) } }.buttonStyle(.borderedProminent)
                    }
                    if entry.status == .uncertain {
                        Button("Vérifier GitHub") { Task { await model.reconcile(entry) } }.buttonStyle(.borderedProminent)
                    }
                    if [.failed, .ignored, .review].contains(entry.status) {
                        Button("Réanalyser la note") { Task { await model.retry(entry) } }.buttonStyle(.bordered)
                    }
                }.disabled(model.busy || model.demo)
                Divider()
                DisclosureGroup("Note d'origine · \(entry.note.folder)") {
                    Text(entry.note.text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                }
                Button("Retrouver la note dans Notes") {
                    if let url = URL(string: entry.note.id), ["x-coredata", "notes"].contains(url.scheme ?? "") {
                        NSWorkspace.shared.open(url)
                    } else { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app")) }
                }.buttonStyle(.link).disabled(model.demo)
            }.padding(32).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
}
