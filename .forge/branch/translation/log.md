# Log — translation

- [2026-09-16] companion-apps.json était doublement encodé en UTF-8 (« Ã© » dans les notices affichées) — réparé en passant les notices en objets traduits ; bug préexistant, hors plan, corrigé au passage.
- [2026-09-16] Périmètre i18n : les quatre scripts (setup, manage-companion-app, create-shortcuts, detect-config). Les throw/warnings des libs (catalogue corrompu, .ico invalide) restent en français : diagnostics d'intégrité, pas des messages d'usage.
- [2026-09-16] Les « notice » de companion-apps.json (affichées dans le journal) passent en objet { fr, en, ja } lu par Get-LocalizedValue (i18n.lib), une chaîne nue restant acceptée — traité en T5.
- [2026-09-16] Sortie console de detect-config.ps1 : alignement en colonnes abandonné (largeur CJK non prévisible), une ligne « libellé : valeur » par élément.
- [2026-09-16] Mode script : messages console dans la langue de Windows (Get-UICulture, repli anglais), même mécanisme que la fenêtre, paramètre -Language optionnel pour forcer — choix utilisateur (option recommandée).
- [2026-09-16] Branche `translation` créée depuis `master` (89ff601), pas depuis `icons` — règle utilisateur, corrigée dans le skill forge (SKILL.md + README + CHANGELOG, dépôt `claude skills/forge`, branche dev).
