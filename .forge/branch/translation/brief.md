# Brief — translation

## Objective

Rendre la fenêtre de configuration (`setup.ps1`) multilingue — français, anglais, japonais. Les chaînes de `setup.ps1`
et les messages du journal produits par `manage-companion-app.ps1` et `create-shortcuts.ps1` sont extraits dans un
dictionnaire de traductions ; la langue par défaut suit celle de Windows (`Get-UICulture`, repli anglais), et
l'utilisateur peut basculer de langue directement dans la fenêtre. Les scripts moteur restent exécutables seuls en
mode script.

## Scope & rules
