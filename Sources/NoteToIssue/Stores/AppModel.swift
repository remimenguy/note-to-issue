import SwiftUI
import AppKit
import ServiceManagement
import NoteToIssueCore

@MainActor
final class AppModel: ObservableObject {
    @Published var settings = Settings()
    @Published var entries: [Entry] = []
    @Published var busy = false
    @Published var monitoring = false
    @Published var keyConfigured = false
    @Published var message = "Connecte OpenRouter dans les réglages pour commencer."
    @Published var error: String?
    @Published var loginMessage = ""
    @Published var connecting = false
    @Published var lastScan: Date?
    @Published var selection: String?
    @Published var filter: EntryStatus?
    let demo = ProcessInfo.processInfo.arguments.contains("--demo")
    private let settingsStore = SettingsStore()
    private let notes: NotesReading = NotesClient()
    private var processor: Processor?
    private var instanceLock: InstanceLock?
    private var loop: Task<Void, Never>?
    private var booted = false
    private var key = ""
    private var oauthServer: OAuthCallbackServer?
    private var oauthTask: Task<Void, Never>?

    var visibleEntries: [Entry] { entries.filter { filter == nil || $0.status == filter } }
    var selected: Entry? { entries.first { $0.id == selection } }
    var publishedCount: Int { entries.filter { $0.status == .published }.count }
    var reviewCount: Int { entries.filter { $0.status == .review || $0.status == .uncertain }.count }

    func boot() async {
        guard !booted else { return }
        booted = true
        if demo { loadDemo(); return }
        do {
            instanceLock = try InstanceLock()
            settings = try settingsStore.load()
            processor = try Processor(journal: Journal())
            await refresh()
            key = try Keychain.read() ?? ""
            keyConfigured = !key.isEmpty
            configureLoginItem()
            if keyConfigured && settings.monitoringEnabled { start() }
            else if keyConfigured { message = "Surveillance en pause." }
        } catch { self.error = error.localizedDescription }
    }

    func save(_ next: NoteToIssueCore.Settings) {
        guard !demo else { message = "La démo ne modifie aucun réglage."; return }
        do {
            try next.validate()
            try settingsStore.save(next)
            settings = next; keyConfigured = !key.isEmpty
            error = nil
            configureLoginItem()
            loop?.cancel(); loop = nil; monitoring = false
            if next.monitoringEnabled && keyConfigured { start() }
            else { message = "Réglages enregistrés. Surveillance en pause." }
        } catch { self.error = error.localizedDescription }
    }

    func beginOpenRouterConnection() {
        guard !demo, !connecting, oauthTask == nil else { return }
        oauthTask = Task { await self.connectOpenRouter() }
    }
    private func connectOpenRouter() async {
        guard !demo, !connecting else { return }
        connecting = true; error = nil
        defer { connecting = false; oauthServer?.cancel(); oauthServer = nil; oauthTask = nil }
        do {
            let pkce = try PKCE()
            let server = try OAuthCallbackServer(state: pkce.state)
            oauthServer = server
            let callback = try await server.start()
            try Task.checkCancellation()
            guard NSWorkspace.shared.open(pkce.authorizationURL(callback: callback)) else {
                throw AppError.message("Impossible d'ouvrir le navigateur.")
            }
            message = "Autorise Note to Issue dans OpenRouter."
            let code = try await server.waitForCode()
            let newKey = try await OpenRouterOAuth().exchange(code: code, verifier: pkce.verifier)
            try Task.checkCancellation()
            try Keychain.save(newKey)
            key = newKey; keyConfigured = true
            message = "OpenRouter est connecté."
            if settings.monitoringEnabled { start() }
        } catch is CancellationError {
            message = "Connexion OpenRouter annulée."
        } catch { self.error = error.localizedDescription }
    }
    func cancelConnection() { oauthTask?.cancel(); oauthServer?.cancel() }

    func checkNotes() async {
        guard !busy, !demo else { return }
        busy = true; defer { busy = false }
        do {
            let batch = try await notes.read(settings: settings, known: [:])
            message = "Accès Notes confirmé · \(batch.count) note(s) disponible(s) dans le premier lot."
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func configureLoginItem() {
        do {
            let service = SMAppService.mainApp
            if settings.launchAtLogin && service.status != .enabled && service.status != .requiresApproval { try service.register() }
            if !settings.launchAtLogin && service.status != .notRegistered { try service.unregister() }
            switch service.status {
            case .enabled: loginMessage = "Lancement à l'ouverture de session activé."
            case .requiresApproval: loginMessage = "Autorise Note to Issue dans les éléments d'ouverture de macOS."
            case .notRegistered: loginMessage = "Lancement automatique désactivé."
            default: loginMessage = "Installe l'app dans Applications pour activer le lancement automatique."
            }
        } catch {
            let diagnostic = error as NSError
            loginMessage = "Lancement automatique à activer dans Réglages Système → Général → Ouverture et extensions (\(diagnostic.domain) \(diagnostic.code))."
        }
    }

    func start() {
        guard !demo, keyConfigured, processor != nil, !monitoring else { return }
        settings.monitoringEnabled = true
        do { try settingsStore.save(settings) } catch { self.error = error.localizedDescription; return }
        monitoring = true
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.scan()
                do { try await Task.sleep(for: .seconds(self.settings.interval)) }
                catch { return }
            }
        }
    }

    func pause() {
        loop?.cancel(); loop = nil; monitoring = false
        settings.monitoringEnabled = false
        do { try settingsStore.save(settings) } catch { self.error = error.localizedDescription }
        message = "Surveillance en pause. Le traitement en cours se termine."
    }

    func scan() async {
        guard !demo, !busy, keyConfigured, let processor else { return }
        busy = true; error = nil; message = "Recherche de nouvelles notes…"
        defer { busy = false }
        let snapshot = settings
        do {
            let batch = try await notes.read(settings: snapshot, known: processor.known)
            var count = 0
            for note in batch {
                if Task.isCancelled { break }
                message = "Analyse \(count + 1)/\(batch.count) : \(note.title)"
                _ = try await processor.process(note: note, settings: snapshot, key: key)
                count += 1
                await refresh()
            }
            lastScan = Date()
            message = count == 0 ? "À jour · aucune nouvelle note à analyser." : "\(count) note(s) traitée(s)."
        } catch {
            self.error = error.localizedDescription
            message = "Analyse interrompue. Le journal est conservé."
            // A durable-state failure stops the loop; service errors remain visible until next timer.
            if !(error is AppError) { pause() }
        }
    }

    func publish(_ entry: Entry) async {
        await action { try await self.processor?.publishReviewed(id: entry.id) }
    }
    func reconcile(_ entry: Entry) async {
        await action { try await self.processor?.reconcile(id: entry.id) }
    }
    func retry(_ entry: Entry) async {
        await action {
            let fresh = try await self.notes.readOne(id: entry.id, settings: self.settings)
            return try await self.processor?.process(note: fresh, settings: self.settings, key: self.key, force: true)
        }
    }
    private func action(_ operation: () async throws -> Entry?) async {
        guard !demo, !busy, processor != nil else { return }
        busy = true; defer { busy = false }
        do { _ = try await operation(); error = nil; await refresh() }
        catch { self.error = error.localizedDescription }
    }
    private func refresh() async {
        guard let processor else { return }
        entries = await processor.entries.values.sorted { $0.updatedAt > $1.updatedAt }
        if selection == nil { selection = entries.first?.id }
    }

    private func loadDemo() {
        let note = Note(id: "demo", title: "Le bouton de connexion ne répond plus", text: "Sur Safari, le bouton Se connecter ne réagit pas après avoir saisi mon e-mail. Il faudrait afficher une erreur et permettre de réessayer.", modifiedAt: Date().timeIntervalSince1970 - 60, folder: "Développement")
        let draft = Draft(isIssue: true, confidence: 0.98, reason: "Bug reproductible dans le parcours de connexion.", title: "Corriger le bouton de connexion sur Safari", body: "## Contexte\nSur Safari, le bouton **Se connecter** ne réagit pas après la saisie de l'adresse e-mail.\n\n## Comportement attendu\nLe clic doit lancer la connexion. En cas d'échec, afficher un message explicite et permettre une nouvelle tentative.\n\n## À vérifier\n- Reproduire le blocage sur Safari.\n- Vérifier la remontée des erreurs dans le formulaire.", labels: ["bug", "enhancement"])
        entries = [Entry(note: note, repository: "kroco-edu/app", status: .review, draft: draft, message: draft.reason)]
        selection = note.id; keyConfigured = false
        message = "Démo locale · aucune note lue, aucun appel réseau."
    }
}
