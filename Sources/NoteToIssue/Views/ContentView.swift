import SwiftUI
import NoteToIssueCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("NOTE TO ISSUE", systemImage: "note.text.badge.plus")
                        .font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(.secondary)
                    Text("Des idées aux\nissues.").font(.system(size: 28, weight: .bold, design: .rounded))
                    HStack(spacing: 6) {
                        Circle().fill(model.monitoring ? .green : .secondary).frame(width: 7, height: 7)
                        Text(model.demo ? "Démonstration" : model.monitoring ? "Surveillance active" : "En pause").font(.caption)
                    }
                }.padding(20)
                Divider()
                List(selection: $model.selection) {
                    Section("Activité") {
                        ForEach(model.visibleEntries.filter { search.isEmpty || $0.note.title.localizedCaseInsensitiveContains(search) || ($0.draft?.title.localizedCaseInsensitiveContains(search) ?? false) }) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.draft?.isIssue == true ? entry.draft!.title : entry.note.title).font(.headline).lineLimit(2)
                                HStack {
                                    StatusBadge(status: entry.status)
                                    Spacer()
                                    Text(entry.repository).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                }
                            }.padding(.vertical, 6).tag(entry.id)
                        }
                    }
                }.listStyle(.sidebar)
                Divider()
                HStack {
                    metric(model.publishedCount, "publiées")
                    Spacer()
                    metric(model.reviewCount, "à vérifier")
                    Spacer()
                    metric(model.entries.count, "traitées")
                }.padding(20)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 380)
        } detail: {
            VStack(spacing: 0) {
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                        .padding().background(.orange.opacity(0.08))
                }
                if let entry = model.selected { EntryDetailView(model: model, entry: entry) }
                else { WelcomeView(model: model) }
                Divider()
                HStack(spacing: 8) {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(model.message).lineLimit(1)
                    Spacer()
                    if let date = model.lastScan { Text(date, style: .time).monospacedDigit() }
                }.font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
        .searchable(text: $search, prompt: "Rechercher une note")
        .toolbar {
            ToolbarItemGroup {
                Picker("Filtrer", selection: $model.filter) {
                    Text("Tout").tag(EntryStatus?.none)
                    Text("Publiées").tag(EntryStatus?.some(.published))
                    Text("À vérifier").tag(EntryStatus?.some(.review))
                    Text("Erreurs").tag(EntryStatus?.some(.failed))
                }.frame(width: 135)
                Button { Task { await model.scan() } } label: { Label("Analyser", systemImage: "arrow.clockwise") }
                    .disabled(model.busy || !model.keyConfigured || model.demo)
                Button { model.monitoring ? model.pause() : model.start() } label: {
                    Label(model.monitoring ? "Pause" : "Démarrer", systemImage: model.monitoring ? "pause.fill" : "play.fill")
                }.disabled(!model.keyConfigured || model.demo)
                SettingsLink { Label("Réglages", systemImage: "gearshape") }
            }
        }
    }

    private func metric(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)").font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct StatusBadge: View {
    let status: EntryStatus
    var color: Color {
        switch status {
        case .published: return .green
        case .review: return .blue
        case .failed, .uncertain: return .orange
        default: return .secondary
        }
    }
    var body: some View {
        Text(status.label).font(.caption2.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3).background(color.opacity(0.10), in: Capsule())
    }
}

struct WelcomeView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "note.text.badge.plus").font(.system(size: 48, weight: .light)).foregroundStyle(.tint)
            Text("Tes notes ont\ndu potentiel.").font(.system(size: 40, weight: .bold, design: .rounded))
            Text("Écris une idée ou un bug dans Notes. OpenRouter prépare une issue claire et la publie dans le bon dépôt, avec ses labels.")
                .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                Label("Compte iCloud · texte des notes uniquement", systemImage: "icloud")
                Label("Destination : \(model.settings.defaultRepository)", systemImage: "arrow.triangle.branch")
                Label("Une note, une issue · doublons contrôlés", systemImage: "checkmark.shield")
                Label("App native · IA distante · veille respectée", systemImage: "leaf")
            }.font(.callout)
            SettingsLink { Text(model.keyConfigured ? "Ouvrir les réglages" : "Configurer OpenRouter").padding(.horizontal, 10).padding(.vertical, 5) }
                .buttonStyle(.borderedProminent)
            Text("Connexion OpenRouter par OAuth PKCE. Les secrets restent dans le Trousseau macOS.")
                .font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: 510, alignment: .leading).padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
