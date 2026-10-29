// Executed by osascript. This script only reads Notes; it never modifies a note.
function run(argv) {
    function isDeletedFolder(name) {
        var normalized = name.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim();
        return ["recently deleted", "deleted notes", "supprimees recemment", "supprimes recemment", "corbeille", "trash"].indexOf(normalized) !== -1;
    }
    var config = JSON.parse(argv[0]);
    var app = Application("com.apple.Notes");
    var accounts = app.accounts.whose({ name: config.account })();
    if (accounts.length === 0 && config.account.toLowerCase() === "icloud") {
        // iCloud accounts can be renamed by the user. Resolve only one explicit iCloud name.
        accounts = app.accounts().filter(function(account) { return /^icloud\b/i.test(account.name()); });
    }
    if (accounts.length !== 1) throw new Error("Notes account not found or ambiguous");
    var account = accounts[0];
    var source = account.notes;
    if (config.folder) {
        var folders = account.folders.whose({ name: config.folder })();
        if (folders.length !== 1) throw new Error("Notes folder not found or ambiguous");
        if (isDeletedFolder(folders[0].name())) return "[]";
        source = folders[0].notes;
    }
    // Two grouped Apple events rather than reading the text of every note.
    var ids = source.id();
    var dates = source.modificationDate();
    var candidates = [];
    for (var i = 0; i < ids.length; i++) {
        if (config.onlyID && ids[i] !== config.onlyID) continue;
        var modified = new Date(dates[i]).getTime() / 1000;
        if (!isFinite(modified) || Date.now() / 1000 - modified < 30) continue;
        if (config.known[ids[i]] === modified || config.known[ids[i]] === -1) continue;
        candidates.push({ id: ids[i], modifiedAt: modified });
    }
    var priorityIDs = config.priorityIDs || [];
    candidates.sort(function (a, b) {
        var first = priorityIDs.indexOf(a.id), second = priorityIDs.indexOf(b.id);
        first = first < 0 ? priorityIDs.length : first;
        second = second < 0 ? priorityIDs.length : second;
        return first - second || b.modifiedAt - a.modifiedAt;
    });
    var result = [];
    for (var j = 0; j < candidates.length && result.length < config.limit; j++) {
        var metadata = candidates[j];
        var note = source.byId(metadata.id);
        var folderName = note.container().name();
        if (isDeletedFolder(folderName)) continue;
        if (note.passwordProtected()) continue;
        var text = note.plaintext();
        // Read a coherent snapshot. Editing during the read is deferred to the next scan.
        if (new Date(note.modificationDate()).getTime() / 1000 !== metadata.modifiedAt) continue;
        result.push({ id: metadata.id, title: note.name(), text: text,
                      modifiedAt: metadata.modifiedAt, folder: folderName });
    }
    return JSON.stringify(result);
}
