# API locale du Riot Client — relevé du 2026-09-20

Riot Client version 139.0.5.4957, Windows 11, mesures faites sur la machine de développement.

## Pourquoi ce relevé

Le raccourci lançait `RiotClientServices.exe --launch-product=league_of_legends --launch-patchline=live`, mais le jeu
ne démarrait pas : la page produit restait ouverte, bouton Play actif. Les journaux du Riot Client
(`%LOCALAPPDATA%\Riot Games\Riot Client\Logs\Riot Client Logs`) montrent la même séquence sur 4 lancements sur 4 :

```
001.410  riot-client-lifecycle: Setting product context to league_of_legends.live, willAutoLaunch=true
001.417  GamePlayPermissionProvider resolved game:play for 'league_of_legends' isGranted=0 reason='UNAUTHORIZED'
001.417  riot-client-lifecycle: Setting product context to league_of_legends.live, willAutoLaunch=false
001.831  GamePlayPermissionProvider resolved game:play for 'league_of_legends' isGranted=1 reason=''
```

L'auto-lancement est accepté, puis annulé 7 ms plus tard parce que la permission `game:play` est arbitrée avant
l'authentification RSO. Elle est accordée 400 ms après, mais l'intention n'est jamais rejouée.

## Accès à l'API

Le lockfile `%LOCALAPPDATA%\Riot Games\Riot Client\Config\lockfile` porte cinq champs séparés par `:` —
`nom:pid:port:mot de passe:protocole`. Le Riot Client garde le fichier ouvert : il faut le lire en partage
(`FileShare.ReadWrite`). L'API écoute en HTTPS sur `127.0.0.1:<port>`, authentification Basic `riot:<mot de passe>`.

## Le transport doit être WinHTTP, pas Invoke-WebRequest

Tous les appels par `Invoke-WebRequest` échouent — « La connexion sous-jacente a été fermée : une erreur inattendue
s'est produite lors de l'envoi » — quelle que soit la version de TLS forcée (Tls11, Tls12, Tls13, combinaisons).
La trace `curl -v` donne la raison :

```
* schannel: renegotiating SSL/TLS connection
* schannel: SSL/TLS connection renegotiated
< HTTP/1.1 200 OK
```

Le serveur demande une renégociation TLS après la requête. `HttpWebRequest`, sur lequel repose `Invoke-WebRequest`,
la refuse par conception. WinHTTP la gère : `WinHttp.WinHttpRequest.5.1` avec l'option `4` (SslErrorIgnoreFlags)
à `13056` pour accepter le certificat auto-signé de la boucle locale — sans toucher au réglage global de .NET,
contrairement à `ServicePointManager.ServerCertificateValidationCallback`.

## Endpoint de lancement

`swagger/v3/openapi.json` expose 792 chemins, mais **aucun endpoint de lancement** : il ne documente que les
plugins, et `product-launcher` est un module natif du client. Les journaux d'un lancement réussi le nomment :

```
000036.140  product-launcher: Launch starting: productId='league_of_legends' patchlineId='live'
```

Routes sondées, dans l'ordre :

| Route | Résultat |
|---|---|
| `POST /product-launcher/v1/products/{productId}/patchlines/{patchlineId}` | **200**, rend un identifiant de session — le jeu démarre |
| `POST /riotclient/new-args` (tableau d'arguments) | 204, mais sans effet : endpoint déprécié, conservé sans comportement |
| `GET /product-session/v1/sessions` | lecture seule, ne lance rien |

## Chronologie d'un démarrage à froid

Riot Client tué puis relancé, POST de lancement rejoué toutes les 700 ms :

```
  2,1s  POST => 0     (lockfile lu, connexion pas encore établie)
  3,8s  POST => 464   (session pas prête — code propre au Riot Client)
  8,2s  POST => 200   (lancement accepté)
  8,3s  client de jeu lancé
```

`/riotclient/region-locale`, `/player-session-lifecycle/v1/session` et `/riotclient/v1/platform-user` répondent
tous les trois **200 dès 7,0 s** — soit avant que le lancement soit accepté. Aucune sonde ne prédit donc l'instant
utile : c'est le lancement lui-même qu'il faut réessayer jusqu'à l'échéance.

## Conclusion retenue

`Wait-RiotProductLaunch` rejoue `POST /product-launcher/v1/products/league_of_legends/patchlines/live` jusqu'à
succès, dans une limite de 30 s (8 s observées à froid). Échec au-delà : repli sur `--launch-product`, puis sur le
bouton Play. Le lanceur complet, mesuré de bout en bout : 17 s entre le clic sur le raccourci et le client de jeu,
`settings.locale` appliqué, `default_locale` intact.

## Complément du 2026-09-20 — la langue par l'API

`PUT /riotclient/product-locales/products/{productId}/patchlines/{patchlineId}`, corps = la locale en chaîne JSON
(`"fr_FR"`), réponse `201`. `GET` sur la même route rend la locale courante.

Mesure décisive, Riot Client allumé :

| Action | Résultat |
|---|---|
| `settings.locale` écrit à la main dans le yaml | revenu à `ja_JP` en quelques secondes — le Riot Client réécrit depuis sa mémoire |
| `PUT "fr_FR"` à l'API | `201`, le Riot Client écrit lui-même le yaml, valeur conservée |
| lancement qui suit | accepté à 3,4 s, client de jeu à 4,0 s, démarré avec `--locale=fr_FR` |

C'est ce qui rend la session chaude exploitable : tant que la langue était écrite dans le dos du Riot Client, il
fallait le fermer pour éviter qu'il l'écrase, et ce redémarrage coûtait l'essentiel du temps de lancement.

Un troisième code d'attente s'est ajouté à `0` et `464` : **`424`**, rendu quand le Riot Client n'a pas encore pris
acte de la fermeture du client de jeu. Il est transitoire, donc traité comme les autres : on réessaie.
