# Restart Race et Skip Intros pour STAR WARS Galactic Racer

Deux mods Lua indépendants pour UE4SS :

- **Restart Race** : ajoute "Recommencer la course" au menu pause des courses de campagne.
- **Skip Intros** : passe les logos de démarrage (Fuse Games, Secret Mode, Lucasfilm).

English version: [README.md](README.md).

Testés le 26/10/2026 sous Windows sur la version Steam du jeu (build 26133805) avec UE4SS
Galactic Racer Edition 0.9.4, puis le 29/10/2026 sous Linux avec Proton.

## Prérequis

[UE4SS Galactic Racer Edition](https://www.nexusmods.com/starwarsgalacticracer/mods/2), installé
dans le dossier du jeu `STAR WARS Galactic Racer\Griffin\Binaries\Win64` (celui qui contient
`SWGR-Win64-Shipping.exe`).

## Installation

1. Fermer le jeu.
2. Télécharger `RestartRace.zip` et/ou `SkipIntros.zip` depuis la page
   [Releases](../../releases).
3. Les extraire **directement dans le dossier `Win64`** ci-dessus. Les fichiers doivent arriver
   dans :
   - `Win64\ue4ss\Mods\RestartRace\` (`enabled.txt`, `config.lua`, `Scripts\main.lua`)
   - `Win64\ue4ss\Mods\SkipIntros\` (`enabled.txt`, `Scripts\main.lua`)
4. Lancer le jeu.

Pour vérifier que les mods sont chargés, ouvrir `Win64\ue4ss\UE4SS.log` : il doit contenir
`[RestartRace] Loaded` et `[SkipIntros] Loaded`.

## Linux (Proton)

Les mods fonctionnent sous Proton, mais UE4SS a besoin d'une option de lancement. UE4SS se
charge par le fichier `dwmapi.dll` du dossier `Win64`, et Wine utilise sa propre version de cette
DLL sauf indication contraire. Dans Steam, clic droit sur le jeu, puis Propriétés, Général,
Options de lancement :

```
WINEDLLOVERRIDES="dwmapi=n,b" %command%
```

Sans cette option, le jeu démarre normalement mais `UE4SS.log` n'est pas mis à jour et les mods
ne font rien.

- Le dossier du jeu est dans la bibliothèque Steam, sous
  `steamapps/common/STAR WARS Galactic Racer/Griffin/Binaries/Win64`. Les mods s'y installent
  comme décrit plus haut.
- Sous Wine, les heures de `UE4SS.log` sont en UTC.
- Les sauvegardes sont dans le préfixe Proton, sous
  `steamapps/compatdata/4078430/pfx/drive_c/users/steamuser/AppData/Local/StarWarsGalacticRacer/Saved/SaveGames/`
  dans le dossier de Steam (`~/.local/share/Steam/` par défaut).

## Désinstallation

Supprimer le dossier du mod dans `Win64\ue4ss\Mods\`. Pour le désactiver sans le supprimer,
renommer son `enabled.txt` (en `enabled.txt.off` par exemple).

## Restart Race

### Fonctionnement

- Le bouton apparaît juste sous "Reprendre", **uniquement pendant une course de campagne qu'on
  peut relancer**. Il est masqué dans la sélection d'événement, après l'arrivée et hors
  campagne (les modes arcade ont déjà leur propre bouton).
- Il se valide à la manette, au clavier ou à la souris.
- Au départ de chaque course, le mod note l'état de la run. Au restart, il le remet avant de
  relancer : crédits d'avant la side bet, santé du véhicule, strikes, pièces défectueuses,
  graine de génération de l'événement et autres valeurs de la run (pour retrouver en principe le
  même tracé).
- Si la course relancée tombe quand même sur un autre tracé, le mod relance encore, jusqu'à 2
  fois (`retry_if_track_changes`). Si le tracé est toujours différent ensuite, la course continue
  sur le nouveau tracé et le log indique `Track still different`.
- Si le jeu n'est pas en "début d'événement" au moment du clic, le restart est annulé sans rien
  modifier et la course continue. Le log indique alors `Restart cancelled`.

### Configuration (`config.lua`)

| Option | Effet |
|---|---|
| `label`, `description` | Texte du bouton et de sa description. `nil` = selon la langue du jeu (français ou anglais). |
| `restore_run_state` | `true` : remet la run dans son état du départ. `false` : simple relance, comme le mod d'origine. |
| `retry_if_track_changes` | `true` : relance encore, jusqu'à 2 fois, si la course relancée tombe sur un autre tracé. `false` : garde le nouveau tracé. |
| `debug` | `true` : détaille chaque restart dans `UE4SS.log` (crédits, santé, pièces, tracé). |

### Ce qui est vérifié en jeu

- Le bouton apparaît tout de suite et le menu reste utilisable, à la manette comme à la souris.
- La course repart du début, sur le même tracé, de nombreuses fois de suite.
- La side bet est remboursée au restart.
- Une pièce tombée en panne pendant la course est réparée au restart, et la course reste sur le
  même tracé.
- Le restart fonctionne aussi dans les courses sans nœud de campagne, comme la première course
  d'une run.
- Skip Intros saute les deux vidéos de logos.

**Problème connu** : sur certains nœuds de la carte, le jeu choisit un autre tracé à chaque fois
qu'il régénère la course, alors que le mod remet le même état de run avant chaque restart. Le
29/10/2026, sur un nœud de l'acte 2, le premier restart et les deux relances automatiques sont
chacun tombés sur un autre tracé. La cause n'est pas encore trouvée.

Avec `debug = true`, le log montre les crédits, les pièces et le tracé avant et après chaque
restart. Les retours sont les bienvenus dans les issues.

## Skip Intros

Le menu du jeu joue `MEDIA_Intro_FUSE_Ident.bk2` puis `MEDIA_Intro_Brand_Ident.bk2` et attend la
fin de chacune. Le mod amène la lecture à la fin de la vidéo dès qu'elle démarre, et le jeu
enchaîne normalement. Les écrans EULA, avertissement épilepsie et "appuyez sur une touche" ne
sont pas touchés. Aucun fichier du jeu n'est modifié.

## Pourquoi une réécriture

Ces mods sont partis de problèmes constatés dans Restart Race 2.0 sur Nexus :

- Le restart utilisait `TravelToStartOrContinueCampaign` sans rien restaurer : side bet perdue,
  pièces abîmées conservées, et parfois un autre tracé.
- Le remboursement guettait une baisse des crédits *après* le restart, alors que la mise est
  débitée avant : il ratait souvent.
- Le bouton était inséré une fois par seconde en démontant le menu, ce qui pouvait bloquer le
  menu pause si on naviguait trop tôt.
- Le clic à la manette n'était pas détecté de façon fiable.
- `config.lua` n'était jamais lu (`require('../config')` ne peut pas fonctionner en Lua).
- Le zip utilisait des `\` dans ses chemins, ce qui n'est pas standard et trompe certains outils.

Le code de ce dépôt est une implémentation indépendante. Merci à GenerousMods pour l'idée
d'origine d'un bouton de restart pour ce jeu.

## Dépannage

- **Rien ne se passe** : regarder `Win64\ue4ss\UE4SS.log`. S'il n'existe pas, UE4SS ne se
  charge pas ou n'a pas le droit d'écrire dans son dossier (Propriétés, Sécurité, autoriser
  l'écriture). Sous Linux, vérifier l'option de lancement (voir [Linux (Proton)](#linux-proton)).
- **Le jeu plante au chargement d'une course** (`Crashdump written to ...\ue4ss\crash_*.dmp`) :
  la v1.1.0 et les versions précédentes plantent dans les courses sans nœud de campagne, comme la
  première course d'une run. C'est corrigé après la v1.1.0 : en attendant la prochaine release,
  remplacer `Scripts\main.lua` par celui de ce dépôt.
- **Après une mise à jour du jeu** : mettre d'abord UE4SS Galactic Racer Edition à jour.
- **Sauvegardes** : `%LOCALAPPDATA%\StarWarsGalacticRacer\Saved\SaveGames\` sous Windows (sous
  Linux, voir [Linux (Proton)](#linux-proton)). En faire une copie avant d'essayer un mod ne
  coûte rien.

## Licence

[MIT](LICENSE). Projet non affilié à Fuse Games, Secret Mode, Lucasfilm ou Disney. STAR WARS est
une marque de Lucasfilm Ltd.
