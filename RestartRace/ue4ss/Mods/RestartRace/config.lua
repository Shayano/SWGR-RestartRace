return {
  -- Texte du bouton et de sa description. Laisser à nil pour suivre la langue du jeu
  -- (français ou anglais), ou mettre un texte entre guillemets pour le forcer.
  label = nil,
  description = nil,

  -- Remet la run dans l'état du départ de la course quand on recommence : crédits (side bet
  -- compris), santé du véhicule, strikes et pièces défectueuses.
  restore_run_state = true,

  -- Si la course relancée tombe sur un autre tracé que celui du départ (le jeu le fait parfois),
  -- relance automatiquement, jusqu'à 2 fois, pour revenir au tracé d'origine. Désactivé par
  -- défaut : ces relances partent pendant l'intro de la course, ce qui peut empêcher de passer
  -- les intros jusqu'au redémarrage du jeu, et elles n'ont pas ramené le tracé d'origine en test.
  retry_if_track_changes = false,

  -- Écrit dans track_diag.log (à côté de ce fichier) le détail de chaque restart, pour trouver
  -- pourquoi le tracé change parfois. Lecture seule, mais peut causer une petite saccade au
  -- départ de la course et au moment du restart.
  track_diagnostics = false,

  -- Écrit le détail de chaque restart dans ue4ss\UE4SS.log (utile pour signaler un bug).
  debug = false,
}
