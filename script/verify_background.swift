import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let bundlePath = CommandLine.arguments.dropFirst().first
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/NoteToIssue.app").path
guard let bundle = Bundle(path: bundlePath), bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true else {
    fail("Le bundle doit définir LSUIElement=true pour éviter l'apparition dans le Dock.")
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.remimenguy.NoteToIssue")
    .first(where: { $0.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: bundlePath).standardizedFileURL.path }) else {
    fail("L'app à vérifier n'est pas démarrée.")
}
guard app.activationPolicy == .accessory else {
    fail("L'app doit rester en mode accessory, sans icône dans le Dock.")
}
print("Vérifié : app active en arrière-plan, sans icône dans le Dock.")
