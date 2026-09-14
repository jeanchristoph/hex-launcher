# Log â€” icons

- [2026-09-14] Cache d'icÃ´nes Explorer : une icÃ´ne composÃ©e regÃ©nÃ©rÃ©e au mÃªme chemin restait affichÃ©e avec l'ancienne couleur â†’ la couleur entre dans le nom du fichier (hex-launcher-fr-blitz-e4103f.ico) et les variantes obsolÃ¨tes sont supprimÃ©es.
- [2026-09-14] Couleurs de pastille fixÃ©es par l'utilisateur d'aprÃ¨s l'identitÃ© de chaque appli : Porofessor #ECEAE4 avec lettre corail #E36A62 (clÃ© optionnelle badge.glyphColor), Blitz #E4103F, OP.GG #645FED, Mobalytics #3D3A69 (ajustÃ©es aprÃ¨s contrÃ´le sur le Bureau) â€” lettre bleu nuit sur pastille claire (rÃ¨gle de contraste, seuil luminance 0,6).
- [2026-09-14] icon.lib.ps1 : chemins rÃ©solus via GetUnresolvedProviderPathFromPSPath (les API .NET ignorent Set-Location) ; copie de bitmap par Clone et non Bitmap(Image), qui arrondit l'alpha.
- [2026-09-14] Protection du logo HL (double licence) : proposÃ©e, refusÃ©e par l'utilisateur â€” tout reste sous MIT. Ne pas reproposer.
- [2026-09-14] Pastille compagnon : lettre Â« O Â» pour OP.GG (pas Â« OP Â»), position haut-droite, composition Ã  la demande sur les .ico de app/ico (pas dans make-flag-icons.ps1) â€” choix utilisateur parmi les options proposÃ©es.
- [2026-09-14] Analyse juridique : logos Blitz/OP.GG/Overwolf soumis Ã  consentement Ã©crit (ToS) â†’ pastille originale couleur + lettre, aucun logo tiers.
- [2026-09-14] Release v0.1.1 publiÃ©e depuis master (icÃ´nes HL pliures attÃ©nuÃ©es, base bleue, variante verte) avant ouverture de la branche icons.
