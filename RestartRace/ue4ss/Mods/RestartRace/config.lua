return {
  -- Texte du bouton et de sa description. Laisser à nil pour suivre la langue du jeu
  -- (français ou anglais), ou mettre un texte entre guillemets pour le forcer.
  label = nil,
  description = nil,

  -- Remet la run dans l'état du départ de la course quand on recommence : crédits (side bet
  -- compris), santé du véhicule, strikes et pièces défectueuses.
  restore_run_state = true,

  -- Écrit le détail de chaque restart dans ue4ss\UE4SS.log (utile pour signaler un bug).
  debug = false,
}
