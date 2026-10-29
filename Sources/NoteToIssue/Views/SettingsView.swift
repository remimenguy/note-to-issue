import SwiftUI
import ServiceManagement
import NoteToIssueCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft = Settings()
    @State private var saved = false
    var body: some View {
        Form {
            Section("OpenRouter") {
                HStack {
                    Label(model.keyConfigured ? "OpenRouter connecté" : "OpenRouter non connecté", systemImage: model.keyConfigured ? "checkmark.circle.fill" : "person.crop.circle")
                    Spacer()
                    if model.connecting {
                        ProgressView().controlSize(.small)
                        Button("Annuler") { model.cancelConnection() }
                    } else {
                        Button(model.keyConfigured ? "Reconnecter" : "Connecter OpenRouter") { model.beginOpenRouterConnection() }
                            .disabled(model.demo)
                    }
                }
                TextField("Modèle", text: $draft.model)
                Text("Connexion OAuth PKCE dans ton navigateur. Le secret obtenu reste dans le Trousseau. Le texte des notes analysées est transmis à OpenRouter.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Notes et GitHub") {
                TextField("Compte Notes", text: $draft.account)
                TextField("Dossier (vide = tous)", text: $draft.folder)
                TextField("Dépôt par défaut", text: $draft.defaultRepository)
                Button("Vérifier l'accès à Notes") { Task { await model.checkNotes() } }.disabled(model.busy || model.demo)
                Text("Dans une note : repo: owner/name pour choisir une autre destination. GitHub utilise ta session gh existante.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Automatisation") {
                Toggle("Publier automatiquement les issues détectées", isOn: $draft.automatic)
                Text("Confiance ≥ 90 %. Les autres propositions attendent une validation. Une note déjà publiée ne crée jamais une seconde issue.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Vérifier les notes toutes les", selection: $draft.interval) {
                    Text("1 minute").tag(60.0)
                    Text("5 minutes · économe").tag(300.0)
                    Text("15 minutes").tag(900.0)
                    Text("1 heure").tag(3600.0)
                }
                Toggle("Reprendre la surveillance au lancement", isOn: $draft.monitoringEnabled)
                Toggle("Ouvrir à la connexion du Mac", isOn: $draft.launchAtLogin)
                Text(model.loginMessage).font(.caption).foregroundStyle(.secondary)
                Button("Éléments d'ouverture macOS") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(.link)
            }
            HStack {
                Text(saved && model.error == nil ? "Réglages enregistrés" : model.error ?? "").font(.caption).foregroundStyle(model.error == nil ? Color.secondary : Color.orange)
                Spacer()
                Button("Enregistrer") { model.save(draft); saved = true }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.demo)
            }
        }.formStyle(.grouped).padding(12).frame(width: 570, height: 720)
            .onAppear { draft = model.settings }
    }
}
