# Note to Issue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Une app macOS légère qui transforme automatiquement les notes iCloud pertinentes en issues GitHub via OpenRouter.

**Architecture:** Cœur Swift testable indépendant de SwiftUI, services Notes/JXA, OpenRouter/URLSession, GitHub/gh. Journal JSON atomique privé, verrou exclusif et publication avec marqueur distant ; UI native app-wide avec surveillance asynchrone.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftUI, Foundation, CryptoKit, Security, XCTest. macOS 14+. Aucune dépendance externe.

**Spec:** `docs/superpowers/specs/2026-10-29-note-to-issue-design.md`

## Global Constraints
- Dépôt par défaut `kroco-edu/app`, seuil automatique 0,90, stabilisation 30 s, intervalle minimum 60 s et lot de 10.
- Secrets uniquement Trousseau/session gh ; aucune clé dans Git.
- Aucun modèle IA local, serveur, webview, OCR ou écriture dans Notes.
- Une note au maximum une issue ; résultat de POST incertain jamais retenté automatiquement.
- Transports externes simulés en tests, aucun envoi réel durant vérifications.

## Review Focus
- Une note cite un dépôt sans demander d'y créer une issue : conserver la destination par défaut.
- Réponse IA erronée, confiance hors bornes, labels inexistants : aucune publication.
- POST accepté puis perte de réponse/arrêt : retrouver le marqueur ou conserver un état bloqué.
- Journal corrompu, second processus ou écriture impossible : arrêter avant POST.
- Notes inchangées, trop longues, verrouillées, encore éditées ou sans compte iCloud : comportement explicite, pas de boucle gourmande.

### Task 1: Models, routing and state
**Files:** `Package.swift`, `Sources/NoteToIssueCore/{Models,Routing,Journal}.swift`, `Tests/NoteToIssueCoreTests/{Routing,Journal}Tests.swift`, `.gitignore`.
**Interfaces:** `Note`, `Draft`, `Settings`, `Entry`; `Routing.repository(for:defaultRepository:) throws -> String`; `Journal.load()/save(_:)`, `InstanceLock`.
- [x] Write routing and journal tests (default, explicit French/English/directive, conflict, invalid repository, marker stability, corruption, lock exclusion and persistence).
- [x] Run `swift test` and observe absent implementation failures.
- [x] Implement validated models, routing, atomic private state and lock.
- [x] Run `swift test`, expected all tests pass; commit.

### Task 2: External services
**Files:** `Sources/NoteToIssueCore/{ProcessRunner,NotesClient,OpenRouterClient,GitHubClient,Keychain}.swift`, `Resources/ReadNotes.js`, service tests.
**Interfaces:** `NotesReading.read(settings:known:) async throws -> [Note]`; `Analyzing.analyze(note:repository:labels:settings:key:) async throws -> Draft`; `GitHubServing.labels/find/create`; injectable `HTTPTransport` and `CommandRunning`.
- [x] Write contract tests for strict structured output, malformed/refused/truncated/error responses, finite confidence and labels, GitHub pagination including closed issues and request body.
- [x] Run `swift test`, expected new tests fail.
- [x] Implement services: fixed HTTPS endpoints, timeout, bounded inputs/output, subprocess argv/stdin, selective Notes metadata scan, Keychain.
- [x] Run `swift test`, expected all pass; commit.

### Task 3: Processing engine
**Files:** `Sources/NoteToIssueCore/Processor.swift`, `Tests/NoteToIssueCoreTests/ProcessorTests.swift`.
**Interfaces:** `Processor.process(note:settings:key:now:) async throws -> Entry`; uses journal and service protocols. `Entry` stores note, fingerprint, draft, status, issueURL and safe diagnostic.
- [x] Write tests for skip unchanged/published, stability window, non-issue caching, low confidence review, existing marker recovery, POST ambiguity, persistence before POST, isolation of failures and changed note invalidation.
- [x] Run `swift test`, expected new tests fail.
- [x] Implement sequential engine, immutable per-scan settings and conservative publication recovery.
- [x] Run `swift test`, expected all pass; commit.

### Task 4: Native app and delivery
**Files:** `Sources/NoteToIssue/{App,Views,Stores}/*.swift`, `script/build_and_run.sh`, `.codex/environments/environment.toml`, `.github/workflows/ci.yml`, `README.md`.
**Interfaces:** main-actor `AppModel` owns settings, processor, journal and scan loop; native SwiftUI WindowGroup + Settings + MenuBarExtra.
- [x] Add model scheduling/configuration tests before implementing relevant behavior.
- [x] Implement setup with SecureField, settings, timeline/detail draft, start/pause, scan once, preview and publication/recovery controls. Add isolated demo data for UI verification.
- [x] Implement reproducible signed local app bundle and French docs, CI.
- [x] Run `swift test`, `./script/build_and_run.sh --verify`, inspect app UI, scan staged files for credentials; commit.
- [x] Fresh whole-branch reviewer, fix important findings with RED→GREEN tests, final complete suite.

## Validation finale
- 40 tests passent avec le moteur SwiftPM par défaut.
- Relecture indépendante : cache des éditions sans changement de texte et annulation OAuth corrigés avec tests RED→GREEN.
- Lecture Notes réelle vérifiée, compte iCloud renommé reconnu et corbeille exclue.
- Signature ad hoc, bundle installé, lancement à la connexion macOS activé.
- Choix final utilisateur : nouvelles notes uniquement, modèle openrouter/free, push et fusion sur main.
