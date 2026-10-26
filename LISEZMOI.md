# Restart Race et Skip Intros pour STAR WARS Galactic Racer

Deux mods Lua indépendants pour UE4SS :

- **Restart Race** : ajoute "Recommencer la course" au menu pause des courses de campagne.
- **Skip Intros** : passe les logos de démarrage (Fuse Games, Secret Mode, Lucasfilm).

English version: [README.md](README.md).

Testés le 26/10/2026 sur la version Steam du jeu (build 26133805) avec UE4SS Galactic Racer
Edition 0.9.4.

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
  relancer : crédits d'avant la side bet, santé du véhicule, strikes, pièces défectueuses et
  graine de génération de l'événement (pour retrouver le même tracé).
- Si le jeu n'est pas en "début d'événement" au moment du clic, le restart est annulé sans rien
  modifier et la course continue. Le log indique alors `Restart cancelled`.

### Configuration (`config.lua`)

| Option | Effet |
|---|---|
| `label`, `description` | Texte du bouton et de sa description. `nil` = selon la langue du jeu (français ou anglais). |
| `restore_run_state` | `true` : remet la run dans son état du départ. `false` : simple relance, comme le mod d'origine. |
| `debug` | `true` : détaille chaque restart dans `UE4SS.log` (crédits, santé, pièces, tracé). |

### Ce qui est vérifié en jeu

- Le bouton apparaît tout de suite et le menu reste utilisable, à la manette comme à la souris.
- La course repart du début, sur le même tracé, de nombreuses fois de suite.
- Une pièce tombée en panne pendant la course est réparée au restart.
- Skip Intros saute les deux vidéos de logos.

**Pas encore vérifié** :

- le remboursement de la side bet (aucune course avec mise pendant les tests) ;
- le maintien du même tracé quand une pièce est tombée en panne pendant la course. En v1.0.0,
  ce cas pouvait mener sur un autre tracé ; la v1.1.0 applique la panne en attente avant de
  restaurer la run, ce qui devrait le corriger.

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
  l'écriture).
- **Après une mise à jour du jeu** : mettre d'abord UE4SS Galactic Racer Edition à jour.
- **Sauvegardes** : `%LOCALAPPDATA%\StarWarsGalacticRacer\Saved\SaveGames\`. En faire une copie
  avant d'essayer un mod ne coûte rien.

## Licence

[MIT](LICENSE). Projet non affilié à Fuse Games, Secret Mode, Lucasfilm ou Disney. STAR WARS est
une marque de Lucasfilm Ltd.
