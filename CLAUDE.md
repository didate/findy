# Findy

Gestionnaire de fichiers pour macOS, **gratuit, open source et natif**. Il tourne à côté du Finder, il ne le remplace pas.

Ce fichier fixe le cadre du projet. En cas de doute sur une décision, c'est lui qui tranche. S'il devient faux, on le corrige dans le même commit que le changement qui le rend faux.

## 1. Vision

**Positionnement** : vitesse et fiabilité d'abord, fonctionnalités ensuite. Les concurrents (ForkLift, Path Finder, QSpace, Commander One) sont payants et chargés de fonctions avancées. Findy vise l'utilisateur normal que le Finder énerve au quotidien.

**Les trois promesses**, dans l'ordre de priorité :

1. **Ne jamais perdre de données.** Aucune opération ne détruit un fichier sans que l'utilisateur l'ait demandé et puisse l'annuler.
2. **Ne jamais figer.** L'interface reste fluide, même sur un dossier de 50 000 fichiers ou un disque réseau lent.
3. **Se souvenir.** Les préférences par dossier (vue, tri, fichiers cachés) sont retenues de façon fiable.

Quand une fonctionnalité entre en conflit avec l'une de ces promesses, la promesse gagne.

**Ce que Findy n'est pas** :

- Pas un remplaçant du Finder : le bureau, la corbeille système et « Afficher dans le Finder » restent au Finder.
- Pas un clone de Norton Commander : le double panneau est une option, pas le mode par défaut.
- Pas une app App Store : le sandbox empêche l'accès complet au disque.

## 2. Périmètre

### MVP v0.1

| # | Fonction | Détail |
|---|----------|--------|
| 1 | Navigation | Barre latérale (favoris, volumes), barre de chemin cliquable et éditable (⌘L), onglets, historique avant/arrière, ⌘↑ pour le parent |
| 2 | Vue liste | `NSTableView`, tri par colonne, dossiers en premier (option), taille des dossiers calculée en arrière-plan |
| 3 | Préférences par dossier | Vue, tri, fichiers cachés, stockés dans notre base, jamais dans des `.DS_Store` |
| 4 | Filtre instantané | Taper filtre la liste du dossier courant |
| 5 | Opérations | Couper/copier/coller (⌘X/⌘C/⌘V), corbeille, renommer, nouveau dossier, undo |
| 6 | Double panneau | Activable (⌘⇧D), copie et déplacement d'un panneau à l'autre |
| 7 | Mise à jour automatique | FSEvents, les vues suivent le disque sans rechargement manuel |

### Après le MVP (ne pas commencer avant que v0.1 soit sortie)

File de copies avec pause, reprise et gestion des conflits. Renommage par lot avec regex et aperçu. Recherche Spotlight limitée au dossier. Navigation dans les archives. Vues icônes et colonnes. SFTP et S3.

**Écarté** : le terminal intégré. « Ouvrir dans le terminal » passe le dossier au terminal de l'utilisateur, et c'est suffisant.

### Règle de périmètre

Une idée hors MVP va dans `docs/ROADMAP.md`, pas dans le code. On ne prépare pas le terrain pour une fonction future (pas d'abstraction « au cas où »).

## 3. Stack technique

| Sujet | Choix | Raison |
|-------|-------|--------|
| Langage | Swift 6, mode de langage Swift 6 (concurrence stricte) | Les API système dont on dépend n'existent qu'en Swift/Obj-C |
| Interface | SwiftUI pour la structure, AppKit pour la liste, le clavier, le glisser-déposer | SwiftUI seul rame au-delà de quelques milliers de lignes |
| Cible | macOS 14 minimum, Apple Silicon et Intel | |
| Projet | XcodeGen (`project.yml`), le `.xcodeproj` n'est pas versionné | Pas de conflits de fusion sur le fichier projet |
| Persistance | SQLite via GRDB pour les préférences par dossier, `UserDefaults` pour les réglages globaux | |
| Sandbox | Désactivé, Hardened Runtime activé | Accès complet au disque |
| Distribution | DMG notarisé et cask Homebrew | |
| Licence | MIT | |

**Rust** : pas dans le MVP. On l'ajoutera en crate `findy-core` (via UniFFI) seulement si une mesure montre que Swift est trop lent sur le parcours de disque, la recherche ou la copie.

**Dépendances** : le moins possible. Toute nouvelle dépendance doit être justifiée (ce qu'elle évite d'écrire, sa licence, son état de maintenance) et validée par l'utilisateur avant d'être ajoutée. Licences acceptées : MIT, BSD, Apache 2.0.

## 4. Architecture

Trois modules, avec des dépendances dans un seul sens : `App → FindyUI → FindyCore`.

```
findy/
├── project.yml              # XcodeGen
├── App/                     # Point d'entrée, Info.plist, Assets.xcassets (icône)
├── Packages/
│   ├── FindyCore/           # Logique, sans aucune interface
│   │   ├── Sources/FindyCore/
│   │   │   ├── FileSystem/  # Listage, attributs, tailles, FSEvents
│   │   │   ├── Operations/  # Copie, déplacement, corbeille, renommage (une opération par élément)
│   │   │   ├── Model/       # FileItem, FileSort, Volume…
│   │   │   └── Store/       # Préférences par dossier (GRDB)
│   │   └── Tests/
│   └── FindyUI/             # Vues SwiftUI et contrôleurs AppKit
│       ├── Sources/FindyUI/
│       │   ├── Browser/     # Panneau, liste (NSTableView), filtre, modèle d'un panneau
│       │   ├── Operations/  # Étapes annulables, historique d'annulation, presse-papiers
│       │   ├── Sidebar/
│       │   ├── PathBar/
│       │   ├── Terminal/    # Ouvrir dans le terminal ou l'éditeur de code, fenêtre Réglages
│       │   ├── Workspace/   # Fenêtre : panneaux, onglets, commandes de menu
│       │   └── Resources/   # Localizable.xcstrings
│       └── Tests/
├── scripts/                 # make-icon.swift (icône), release.sh (DMG de release)
├── packaging/homebrew/      # Formule Homebrew (cask)
└── docs/                    # ROADMAP.md, decisions/
```

**Règles** :

- `FindyCore` n'importe ni SwiftUI ni AppKit. Il doit pouvoir être testé en ligne de commande avec `swift test`.
- Les vues ne touchent jamais le disque. Elles passent par un modèle (`@Observable`, `@MainActor`) qui appelle `FindyCore`.
- Tout accès au système de fichiers passe par un protocole de `FindyCore` (`FileSystemProviding`), pour pouvoir le remplacer par un faux en test.
- Un type par fichier, le fichier porte le nom du type.

## 5. Règles de fiabilité (non négociables)

1. **Suppression = corbeille.** On utilise `FileManager.trashItem`. La suppression définitive demande une action distincte et une confirmation explicite.
2. **Jamais d'écrasement silencieux.** Si la destination existe, on demande (remplacer, garder les deux, ignorer). « Garder les deux » est le choix par défaut.
3. **Un déplacement entre volumes est une copie vérifiée, puis une suppression de la source.** La source n'est supprimée que si la copie a réussi en entier.
4. **Toute opération est annulable** (⌘Z) tant que c'est techniquement possible, et l'annulation est enregistrée avant de déclarer l'opération réussie.
5. **Toute opération longue est annulable en cours de route** et laisse le disque dans un état propre (pas de fichier à moitié copié qui traîne).
6. **Les erreurs remontent jusqu'à l'utilisateur**, avec le chemin concerné et la cause. Pas de `try?` qui avale une erreur sur une opération de fichier. Pas de `try!` ni de `fatalError` hors des tests.
7. **Les liens symboliques ne sont jamais suivis** pendant une copie, une suppression ou un calcul de taille, sauf demande explicite.
8. **Fichiers cloud (File Provider)** : on ne déclenche jamais le téléchargement d'un fichier juste pour l'afficher ou calculer une taille. On lit les attributs sans matérialiser le contenu.

## 6. Règles de performance

1. **Zéro E/S sur le thread principal.** Listage, attributs, tailles, icônes : tout est asynchrone. Le thread principal ne fait que de l'affichage.
2. **Affichage progressif** : un dossier s'ouvre tout de suite, les lignes arrivent par lots, les tailles et les icônes se remplissent ensuite.
3. **Tout travail en arrière-plan est annulé** quand l'utilisateur quitte le dossier (annulation de `Task`).
4. **Budgets** à tenir sur un Mac Apple Silicon, SSD interne :

   | Mesure | Budget |
   |--------|--------|
   | Ouverture d'un dossier de 10 000 fichiers (premières lignes visibles) | < 100 ms |
   | Listage complet de 10 000 fichiers | < 300 ms |
   | Défilement de la liste | 60 images/s, sans saccade |
   | Filtre instantané sur 10 000 fichiers | < 16 ms par frappe |
   | Lancement à froid jusqu'à la première fenêtre | < 500 ms |

5. **On mesure avant d'optimiser** (Instruments, `XCTMetric`). Pas d'optimisation sans chiffre avant et après.
6. Listage par lots avec `getattrlistbulk` ou `FileManager.enumerator` avec les clés de ressource préchargées. Jamais un `stat` par fichier.

## 7. Conventions de code

- **Langue** : code, identifiants, commentaires, messages de commit et documentation du dépôt (`README`, `docs/`) en **anglais**. Les échanges avec l'utilisateur sont en **français**.
- **Interface** : toutes les chaînes visibles passent par un String Catalog (`Localizable.xcstrings`). Anglais en langue de base, français fourni dès le MVP. Aucune chaîne en dur dans les vues.
- **Style** : conventions de l'API Design Guidelines de Swift. Formatage par `swift-format` avec la configuration du dépôt.
- **Concurrence** : `async/await` et acteurs. Pas de `DispatchQueue` ni de verrous dans le nouveau code, sauf pour envelopper une API système qui l'exige. Pas de `@unchecked Sendable` sans commentaire qui explique pourquoi c'est sûr.
- **État** : macro `@Observable`, pas `ObservableObject`.
- **Erreurs** : types d'erreur précis par domaine (`FileOperationError`…), pas de `NSError` générique qui remonte dans l'interface.
- **Commentaires** : ils expliquent le pourquoi, pas le quoi. Tout contournement d'un bug système cite le comportement observé et la version de macOS.
- **Accessibilité** : chaque contrôle a un libellé VoiceOver, toute action est faisable au clavier.
- **Aspect** : contrôles et couleurs système, mode clair et sombre, pas de couleurs codées en dur.

## 8. Tests

- `FindyCore` : tests unitaires obligatoires pour toute logique. Les opérations de fichiers sont testées sur de vrais fichiers dans un dossier temporaire, créé et détruit par le test.
- Cas à couvrir pour chaque opération de fichier : nom en conflit, permission refusée, lien symbolique, nom avec Unicode ou emoji, fichier très long, annulation en cours de route, undo.
- `FindyUI` : tests des modèles de vue. Pas de tests d'interface automatisés dans le MVP.
- Un bug corrigé arrive avec le test qui le reproduit.
- **Les tests ne touchent jamais les vrais dossiers de l'utilisateur** (`~/Documents`, `~/Desktop`…). Uniquement `FileManager.temporaryDirectory`.

## 9. Commandes

```bash
xcodegen generate                                   # (re)générer Findy.xcodeproj
xcodebuild -scheme Findy -configuration Debug build # compiler l'app
swift test --package-path Packages/FindyCore        # tests du cœur
swift test --package-path Packages/FindyUI          # tests des modèles de vue
xcrun swift-format lint --recursive App Packages    # vérifier le style
swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset  # régénérer l'icône
```

`swift test` télécharge GRDB au premier lancement. Pour essayer l'app sur un dossier précis : `open Findy.app --args /chemin/du/dossier`.

## 10. Git

- Branche principale : `main`, toujours compilable et tests au vert.
- Une branche par sujet : `feat/…`, `fix/…`, `refactor/…`, `docs/…`.
- Commits au format Conventional Commits, en anglais, à l'impératif : `feat(browser): add instant filter`.
- Un commit = un changement cohérent qui compile.
- **Aucune mention d'un outil d'IA dans les commits ni dans les PR** (ni « Generated with », ni « Co-Authored-By »).
- Jamais de `git push --force` sur `main`. Jamais de commit ni de push sans que l'utilisateur l'ait demandé.

## 11. Façon de travailler (pour Claude)

- **Avant de coder une fonction**, vérifier qu'elle est dans le périmètre du MVP (section 2). Sinon, le dire et proposer de l'ajouter à la feuille de route.
- **Avant de dire que c'est fini** : le projet compile, les tests passent, et la fonction a été lancée et vérifiée dans l'app. Si une vérification n'a pas pu être faite, le dire clairement.
- **Pendant le développement et les essais**, ne manipuler que des fichiers de test dans un dossier temporaire. Ne jamais lancer une opération destructive sur les fichiers réels de l'utilisateur.
- **Demander avant** : d'ajouter une dépendance, de changer l'architecture (section 4), de changer la cible macOS, ou de toucher à une règle de ce fichier.
- **Décisions d'architecture** importantes : une note courte dans `docs/decisions/` (contexte, choix, alternatives écartées).
- Préférer les petites étapes livrables : chaque étape laisse l'app dans un état utilisable.
- Quand une API système se comporte de façon inattendue, écrire un test minimal qui le montre avant de construire un contournement.
