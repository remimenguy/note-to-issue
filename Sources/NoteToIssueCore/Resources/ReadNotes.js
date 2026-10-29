// Executed by osascript. This script only reads Notes; it never modifies a note.
function run(argv) {
    var config = JSON.parse(argv[0]);
    var app = Application("com.apple.Notes");
    var accounts = app.accounts.whose({ name: config.account })();
    if (accounts.length !== 1) throw new Error("Notes account not found or ambiguous");
    var account = accounts[0];
    var source = account.notes;
    if (config.folder) {
        var folders = account.folders.whose({ name: config.folder })();
        if (folders.length !== 1) throw new Error("Notes folder not found or ambiguous");
        source = folders[0].notes;
    }
    // Two grouped Apple events rather than reading the text of every note.
    var ids = source.id();
    var dates = source.modificationDate();
    var candidates = [];
    for (var i = 0; i < ids.length; i++) {
        var modified = new Date(dates[i]).getTime() / 1000;
        if (!isFinite(modified) || Date.now() / 1000 - modified < 30) continue;
        if (config.known[ids[i]] === modified || config.known[ids[i]] === -1) continue;
        candidates.push({ id: ids[i], modifiedAt: modified });
    }
    candidates.sort(function (a, b) { return b.modifiedAt - a.modifiedAt; });
    var result = [];
    for (var j = 0; j < candidates.length && result.length < config.limit; j++) {
        var metadata = candidates[j];
        var note = source.byId(metadata.id);
        if (note.passwordProtected()) continue;
        var text = note.plaintext();
        // Read a coherent snapshot. Editing during the read is deferred to the next scan.
        if (new Date(note.modificationDate()).getTime() / 1000 !== metadata.modifiedAt) continue;
        result.push({ id: metadata.id, title: note.name(), text: text,
                      modifiedAt: metadata.modifiedAt, folder: note.container().name() });
    }
    return JSON.stringify(result);
}
