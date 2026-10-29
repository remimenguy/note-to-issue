# Note to Issue — conception

## Demande et décisions utilisateur
- Application locale sur le Mac, dépôt public cloné dans le dossier Projets du disque externe.
- Lire les notes iCloud, détecter avec OpenRouter les demandes de développement, reformuler l'issue et choisir ses labels.
- Créer automatiquement les issues détectées dans `kroco-edu/app`, sauf destination explicitement écrite dans la note.
- Aucun secret dans Git.

## Choix de réalisation
- App native SwiftUI, macOS 14+, paquet Swift sans dépendance externe. Fenêtre principale, réglages et menu dans la barre des menus.
- Notes est interrogé via son interface d'automatisation officielle (JXA/osascript), sans accéder à sa base privée. Permission macOS demandée au premier accès.
- Compte `iCloud` par défaut, filtre de dossier facultatif. Texte seulement ; notes verrouillées ignorées, pas d'OCR ni de pièces jointes.
- Un bouton démarre la surveillance toutes les 60 secondes tant que l'app est ouverte. Le mode de publication est automatique par défaut ; un mode aperçu reste disponible.
- Stabilisation de 30 secondes après la dernière modification pour éviter de publier une note en cours d'écriture.
- Clé OpenRouter enregistrée uniquement dans le Trousseau. Authentification GitHub via la session locale `gh` existante. Aucun token dans les arguments ou fichiers du dépôt.
- Modèle OpenRouter configurable, réponse JSON Schema et validation locale ; aucune commande générée par l'IA n'est exécutée. L'IA reçoit uniquement le texte de la note, le dépôt choisi et ses labels existants.
- Notes personnelles, listes de courses, journaux et demandes vagues sont ignorés. Les détections sous 0,90 de confiance restent en aperçu.
- Routage déterministe : `repo: owner/name`, `repository: owner/name`, `dépôt: owner/name`, ou une instruction comme `dans le repo owner/name` / `create issue in owner/name`. Une simple référence à un autre dépôt ne change pas la destination. Directives conflictuelles ou mal formées : erreur, aucune publication.
- Les labels proviennent uniquement des labels déjà présents dans le dépôt. L'app ne crée pas de nouveaux labels.
- Une note produit au maximum une issue. La réécriture porte sur le titre et la description de l'issue. La note source reste intacte ; son lien et le lien GitHub sont accessibles dans l'app.
- Journal local atomique dans `~/Library/Application Support/NoteToIssue`, permissions privées ; détections négatives mémorisées jusqu'à modification du texte.
- Identifiant de note haché dans un marqueur HTML de l'issue. Avant création, recherche de ce marqueur dans toutes les issues du dépôt, ouvertes et fermées, via pagination. Une publication au résultat incertain passe en état à vérifier et n'est jamais retentée automatiquement. Le journal n'est pas effacé quand la note est modifiée après publication.
- Verrou local exclusif empêchant deux instances de publier simultanément. Erreur de journal : arrêt avant tout nouvel envoi. Une erreur sur une note n'empêche pas de traiter les autres.
- Pas d'envoi réel de notes à l'IA ni d'issue créée pendant les tests automatisés. Une démo locale permet de vérifier l'interface sans clé.

## Livraison et validation
- README en français : lancement, permissions Notes, clé OpenRouter, syntaxe de destination, fonctionnement automatique, confidentialité et récupération après erreur.
- Script reproductible produisant `dist/NoteToIssue.app`, configuration du bouton Run Codex, workflow CI macOS.
- Tests du routage, validation IA, cache, journal, doublons, reprises, erreurs réseau et contrat OpenRouter/GitHub avec transports simulés.
- Vérification locale : `swift test`, build, lancement de l'app et contrôle du processus. Pas de push demandé ; code conservé dans le clone local, prêt à être publié.

## Ressources (demande utilisateur)
- Priorité à une consommation très faible : pas de serveur local, de webview, de modèle local ou de dépendance externe.
- Lecture groupée des identifiants et dates de modification ; seuls les textes nouveaux/modifiés sont récupérés.
- Un seul scan à la fois, un seul appel IA à la fois, au maximum 10 notes par scan, intervalle configurable à partir de 60 secondes.
- Au repos : timer suspendu entre les passages. Les analyses négatives et aperçus ne sont pas recalculés sans modification. Les erreurs sont visibles et ne provoquent pas de boucle active.
- Fonctionnement continu via menu de barre des menus, même fenêtre fermée. Installation du bundle dans `~/Applications` pour ne pas dépendre du montage du disque externe.
- Démarrage à l'ouverture de session via `SMAppService.mainApp`. Activation macOS signalée si approbation système requise. Surveillance reprise automatiquement lorsque la clé est configurée ; pause persistante.
- En veille/arrêt aucune activité, reprise au réveil/ouverture de session. Aucun maintien artificiel du Mac éveillé.
