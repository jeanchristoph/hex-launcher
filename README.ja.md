# hex-launcher

[English](README.md) · [Français](README.fr.md) · **日本語**

> **Riot Games とは無関係のプロジェクトです。** hex-launcher は Riot Games の[「Legal Jibber Jabber」](https://www.riotgames.com/en/legal)ポリシーのもとで作成されました。Riot Games はこのプロジェクトを支持・後援していません。League of Legends および Riot Games は Riot Games, Inc. の商標または登録商標です。このプロジェクトには Riot の画像素材は含まれず、アイコンはすべてオリジナルです。

**現時点では Windows 専用です**（Windows 10/11、PowerShell 5.1 同梱 — macOS は非対応）。

Windows 向け League of Legends 起動アシスタント：デスクトップのショートカットから、好きな言語（日本語、フランス語など）で
ゲームを起動します。小さなアニメーション付きスプラッシュを表示し、黒いコンソール画面は出ません。
さらに**補助アプリ**（Porofessor、Blitz、OP.GG、Mobalytics）を管理します — 使いたいものにチェックを入れると
ツールがインストールし、言語 × 補助アプリごとにショートカットが作られます
（`League of Legends JP - Blitz`、`League of Legends JP - Porofessor` など）。

## フォルダーの内容

| ファイル | 役割 |
|---|---|
| `install.bat` | **これをダブルクリック**：インストールアシスタントを開きます（1 つのウィンドウ：検出、補助アプリ、ショートカット） |
| `LISEZMOI.txt` | 3 行のクイックスタート（仏／英） |
| `app/` | エンジン — 編集不要 |
| `app/install.ps1` | インストールアシスタント（LoL テーマの単一ウィンドウ） |
| `app/config.json` | Riot のパスと補助アプリの一覧。`install.bat` が生成。検出がうまくいかない場合は手動編集可 |
| `app/locales.json` | インストール時に選べる言語のカタログ（Riot のコード＋表示名） |
| `app/companion-apps.json` | 補助アプリのカタログ：各アプリの検出・インストール・アンインストール・起動方法と、バイナリの署名者 |
| `app/launch-lol.ps1` | ランチャー本体：Riot Client を終了し、言語を強制設定し、ゲームを再起動（＋ `-Companion` で指定した補助アプリ） |
| `app/detect-config.ps1` | `install.bat` から呼ばれる：Riot と既にインストール済みの補助アプリを検出 |
| `app/manage-companion-app.ps1` | `install.bat` から呼ばれる：補助アプリの選択、不足分のインストール、要求時のアンインストール |
| `app/create-shortcuts.ps1` | `install.bat` から呼ばれる：言語と補助アプリの選択ダイアログを表示し、組み合わせごとに `.lnk` をデスクトップに作成（デスクトップに書き込めない場合はこのフォルダーに作成） |
| `app/lib/companion-app.lib.ps1` | 共通関数：カタログ、レジストリによる検出（読み取り専用）、アンインストールコマンド、Authenticode 署名検証 |
| `app/lib/launch-config.lib.ps1` | 共通関数：`config.json` の読み書き、旧形式（単一アプリ）からの移行 |
| `app/lib/splash.lib.ps1` | 共通のアニメーション付きスプラッシュ（ゲーム起動、補助アプリのインストール） |
| `tests/` | Pester テスト（`Invoke-Pester -Path tests`） |
| `app/make-flag-icons.ps1` | ツール：オリジナルの基本アイコンから `ico/` の国旗アイコンを再生成（通常の使用には不要） |
| `app/lib/icon.lib.ps1` / `icon-badge.lib.ps1` | `.ico` の読み書きと、国旗アイコンへの補助アプリバッジの合成 |
| `app/ico/` | アイコン：オリジナルの基本アイコン（H モノグラム）＋言語ごとの国旗バージョン（`hex-launcher-xx.ico`）。`ico/companion/` にはこの PC で合成された国旗＋バッジのアイコンが入ります |

## 新しい PC へのインストール

0. **[最新版をダウンロード](https://github.com/jeanchristoph/hex-launcher/releases/latest)**（`hex-launcher-x.y.z.zip`）して展開するか、リポジトリをクローンします。
1. このフォルダーを好きな場所にコピーします（例：`Documents\hex-launcher`）。別の PC から持ってきた場合は、
   検出が正しく動くように **`config.json` を含めない**でください。
2. **`install.bat`** をダブルクリックします（「管理者として実行」は不可：ツールは意図的に拒否します）。3 つのステップ：
   - **[1/3] 検出** — Riot Client を検出（Riot 公式のファイル `RiotClientInstalls.json` を使用）し、カタログの補助アプリのうち
     既にインストール済みのものをすべて検出し、`config.json` を書き出します（既に存在する場合は上書きしません：手動設定は保持されます）；
   - **[2/3] 補助アプリ** — カタログの各アプリがチェックボックス付きで表示され、前回の選択（なければインストール済みのもの）が
     チェック済みです。チェックしたアプリで未インストールのものがインストールされます。**既定でオフ**の別のチェックボックスで、
     チェックを外した既存アプリのアンインストールも選べます。確認画面に実行内容が正確に列挙されます。「Annuler」なら何も変更しません；
   - **[3/3] ショートカット** — 言語（初回は JP と FR が選択済み）と、組み合わせる補助アプリにチェックするダイアログ。
     言語 × 補助アプリごとに 1 つのショートカットをデスクトップに作成します（`League of Legends JP - Blitz`）。
     補助アプリのチェックがなければ単に `League of Legends JP`。このランチャーの不要になったショートカットは削除されます。
     デスクトップに書き込めない場合（保護されたフォルダー、OneDrive など）は、代わりにこのフォルダーに作成します。
3. 使いたい言語と補助アプリのショートカットをダブルクリックします。

後から言語や補助アプリを追加・削除するには：`install.bat` を再実行してください。

検出が間違っていた場合は：`app\config.json` を編集（下記参照）して `install.bat` を再実行。
検出をやり直すには：`app\config.json` を削除して再実行してください。

新しい言語で初めて起動するとき、Riot Client がテキスト＋ボイスパック（数百 MB）をダウンロードします。正常な動作です。

## 補助アプリ

複数の補助アプリを共存させられます。各ショートカットはゲームの後にそのうち 1 つだけを起動し、**その前に他のアプリを閉じます**
（オーバーレイが 2 つ同時だと競合します）— 補助アプリなしのショートカットはすべて閉じます。Porofessor の場合は Overwolf クライアントを閉じることになります。
「アンインストール」のチェックを入れない限り（または `-UninstallOthers` を渡さない限り）、何もアンインストールされません。

| アプリ | インストール | アンインストール |
|---|---|---|
| **Porofessor**（Overwolf） | Overwolf 公式インストーラー、サイレント（約 10 秒、Overwolf が既にある場合）。Overwolf がない場合は Overwolf のセットアップ画面が表示されるので、その手順に従ってください（約 1 分、UAC の確認が出ることがあります） | **対話式**：Overwolf 自身のアンインストールメニューが開き、*Overwolf* **と** *Porofessor* の両方にチェックが入っています。他のアプリで Overwolf を使っている場合は Overwolf のチェックを外してから Uninstall をクリックしてください。ツールが勝手に決めることはありません |
| **Blitz** | `winget install Blitz.Blitz`、サイレント（約 15 秒） | サイレント |
| **OP.GG** | `op.gg` の公式インストーラー、サイレント（約 10 秒） | サイレント |
| **Mobalytics** | `mobalytics.gg` の公式スタンドアロンインストーラー、サイレント（約 10 秒） | サイレント |

安全規則（すべてコードで強制）：
- ツールは昇格（管理者）での実行を拒否します — インストーラーはユーザー単位で、アンインストールコマンドは
  あなたのどのプログラムでも書き換えられるユーザーレジストリから読まれるためです；
- 実行するすべてのバイナリ — ダウンロードしたインストーラー**も**レジストリから読んだアンインストーラーも — は、
  カタログに記載された発行者（`Overwolf Ltd`/IL、`OP.GG`/KR、Blitz は `Swift Media Entertainment, Inc.`/US、
  Mobalytics は `GAMERS NET, INC.`/US）の有効な Authenticode 署名が必要です。未署名や想定外の発行者 → 拒否し、
  Windows の「インストールされているアプリ」を使うよう案内します；
- ツール自身は Windows レジストリに書き込みません：`Uninstall` キーを**読む**だけです；
- セットアップがアプリを起動してしまう場合（Mobalytics）は閉じます — アプリはゲームと一緒に起動します。

自動インストールができない場合（winget がない、ネットワーク不通）は、公式ダウンロードページがブラウザーで開きます：
自分でインストールすれば、ランチャーはアプリが存在し次第それを使います。

Overwolf アプリのアンインストール後、Overwolf はブラウザーでフィードバックページを開きます。閉じて構いません。

スクリプトでの使用（配布）：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File app\manage-companion-app.ps1 -Apps blitz,opgg                   # 確認ダイアログあり
powershell -NoProfile -ExecutionPolicy Bypass -File app\manage-companion-app.ps1 -Apps blitz -UninstallOthers -Force # ダイアログなし
powershell -NoProfile -ExecutionPolicy Bypass -File app\manage-companion-app.ps1 -Apps none -DryRun                 # 実行内容の表示のみ
powershell -NoProfile -ExecutionPolicy Bypass -File app\create-shortcuts.ps1 -Locales ja_JP,ko_KR -Companions blitz,opgg
```
ID：`porofessor`、`blitz`、`opgg`、`mobalytics`、`none`。終了コード：0 成功 · 1 エラー · 2 キャンセルまたは拒否。

### カタログにアプリを追加する

`companion-apps.json` に 1 エントリ追加します。リストの順序が検出の優先順位です。

```json
{
  "id": "opgg",
  "name": "OP.GG",
  "signer":       { "organization": "OP.GG", "country": "KR" },
  "badge":        { "glyph": "O", "color": "#1FA8D8" },
  "processNames": ["OP.GG"],
  "launch":    { "path": "%LOCALAPPDATA%\\Programs\\OP.GG\\OP.GG.exe", "arguments": "" },
  "detect":    { "registryDisplayNamePattern": "^OP\\.GG", "path": "%LOCALAPPDATA%\\Programs\\OP.GG\\OP.GG.exe" },
  "install":   { "strategy": "download", "url": "https://op.gg/desktop/download/latest", "arguments": "/S /currentuser",
                 "timeoutSeconds": 180, "fallback": "browser", "browserUrl": "https://op.gg/desktop" },
  "uninstall": { "mode": "silent" }
}
```

| キー | 説明 |
|---|---|
| `badge.glyph` / `badge.color` / `badge.glyphColor` | このアプリのショートカットに付くバッジ：`#RRGGBB` 色の円に 1 文字（最大 2 文字）。ランチャーが描画し、第三者のロゴは使いません。`glyphColor`（任意）は文字色を指定します。省略時は明るい円に暗い文字、暗い円に白い文字になります。バッジが未設定または無効なら国旗アイコンのみになります |
| `signer.organization` / `signer.country` | 発行者のコード署名証明書の `O=` と `C=`。完全一致、大文字小文字を区別。`Get-AuthenticodeSignature <exe>` → `SignerCertificate.Subject` で確認できます。すべてのアプリで必須：ないとインストーラーもアンインストーラーも拒否されます |
| `processNames` | アンインストール前、およびアプリを起動してしまったインストール後に終了させるプロセス |
| `launch.path` / `launch.arguments` | ゲームの後にランチャーが起動するもの。環境変数 `%VAR%` は展開されます |
| `detect.registryDisplayNamePattern` | レジストリの `Uninstall` キー（HKLM、HKLM\WOW6432Node、HKCU）の `DisplayName` と照合する正規表現。OP.GG と Mobalytics は名前にバージョンを含むため前方一致パターン |
| `detect.path` | 代替：このパスが存在すればインストール済みとみなす |
| `install.strategy` | `winget`（＋ `wingetId`）、`download`（＋ https の `url`、`arguments`）または `browser`（＋ https の `browserUrl`） |
| `install.fallback` | 主戦略が失敗したときに使う戦略（通常は `browser`）。その戦略の必須フィールドも必要です |
| `install.timeoutSeconds` | インストーラー終了後にアプリの出現を待つ最大時間（終了コードは信頼できません：NSIS アンインストーラーは非同期、Overwolf は成功時も 1223 を返します）。必須、0 より大きい値 |
| `install.notice` | インストール前の確認に表示する文（例：Overwolf のセットアップ画面についての注意） |
| `uninstall.mode` | `silent`（`QuietUninstallString`、なければ `UninstallString` + `/S`）または `interactive`（`UninstallString` をそのまま実行、発行者が独自のダイアログを表示） |
| `uninstall.dialogProcessNames` | 対話式：待機する発行者ダイアログのプロセス（Overwolf：`OWUninstallMenu`） |
| `uninstall.notice` | アンインストール前の確認に表示する文（例：Overwolf の注意） |

## `app\config.json`

```json
{
  "riotClientPath": "C:\\Riot Games\\Riot Client\\RiotClientServices.exe",
  "productSettingsPath": "C:\\ProgramData\\Riot Games\\Metadata\\league_of_legends.live\\league_of_legends.live.product_settings.yaml",
  "companionApps": [
    { "id": "porofessor", "name": "Porofessor", "path": "C:\\Program Files (x86)\\Overwolf\\OverwolfLauncher.exe",
      "arguments": "-launchapp pibhbkkgefgheeglaeemkkfjlhidhcedalapdggh -from-startmenu" },
    { "id": "blitz", "name": "Blitz", "path": "C:\\Users\\<ユーザー名>\\AppData\\Local\\Programs\\Blitz\\Blitz.exe", "arguments": "" }
  ]
}
```

バックスラッシュは二重（`\\`）にしてください — JSON のためです。`companionApps` は `manage-companion-app.ps1` が
カタログから書き込みます。カタログにないアプリのために手動でエントリを追加することもできます（任意の `id`、`-Companion` で使用）。
旧バージョンの `config.json`（単一の `companionApp` ブロック）は次回読み込み時に自動的に移行されます。

| キー | 説明 |
|---|---|
| `riotClientPath` | `RiotClientServices.exe` のパス。既定は `C:\Riot Games\Riot Client\`。 |
| `productSettingsPath` | Riot が LoL の言語を保存する yaml ファイル。特殊なインストールでない限り `C:\ProgramData\Riot Games\Metadata\…` 配下。 |
| `companionApps[].id` | ショートカットが使う識別子（`launch-lol.ps1 -Companion <id>`）。 |
| `companionApps[].name` | スプラッシュに表示される名前。見た目のみ。 |
| `companionApps[].path` | 起動する実行ファイル。 |
| `companionApps[].arguments` | 起動引数。なければ空文字 `""`。 |

`path` がこの PC に存在しない場合、ランチャーはそれをスキップしてスプラッシュに警告を表示します — ゲームは起動します。
ショートカットが一覧にない `id` を要求した場合も同様です。

**その他の Overwolf アプリ**：`OverwolfLauncher.exe` はそのままに、`-launchapp` の後の識別子を置き換えます
（アプリがスタートメニューに作成したショートカットのプロパティで確認できます）。

## 言語

Riot が提供するすべての言語が `locales.json` にあり、インストール時に選択できます。ショートカット名は
`League of Legends XX`（XX = コードの国部分：`ja_JP` → JP、`ko_KR` → KR）で、補助アプリが付く場合は ` - <補助アプリ>` が続きます。

アイコン：各ショートカットにはその言語の国旗バリエーション（`app/ico/hex-launcher-xx.ico`、例：`ja_JP` は `hex-launcher-jp.ico`）が
設定されます。国旗がない言語には基本アイコン `app/ico/hex-launcher.ico` が使われます。
補助アプリ付きのショートカットには右上に色付きバッジが加わります — P Porofessor、B Blitz、O OP.GG、M Mobalytics —
インストール時に `app/ico/companion/` に合成されます（32 px 未満では文字が省かれ、色だけが残ります）。

カタログにない言語（Riot の新しいロケール）を追加するには：
1. yaml ファイルの `available_locales` にある正確なコードで `locales.json` に 1 行追加；
2. （任意）`make-flag-icons.ps1` の `$FlagDrawings` に国旗の描画を追加し、
   `powershell -NoProfile -ExecutionPolicy Bypass -File app\make-flag-icons.ps1 -Locales xx_XX` を実行。

## 仕組み

Riot Client の「言語」設定はランチャーの言語を変えるだけで、ゲームの言語は変わりません。LoL の言語は
`product_settings.yaml` の `settings.locale` から読み込まれ、Riot Client は終了するたびにこのファイルを書き直します。
そのためランチャーは次の順序で処理します：

1. Riot Client と LoL クライアントが起動していれば終了する（そうしないと変更が上書きされます）。
2. `settings.locale` を指定の言語に書き換える（Riot が管理する `default_locale` は変更しません）。
3. 念のため `--locale=xx_XX` を付けて Riot Client を起動する。
4. `config.json` の他の補助アプリを閉じてから、`-Companion` で指定された補助アプリがあれば起動する。

## テスト

Pester 3.4 は Windows PowerShell 5.1 に同梱されています — 追加インストール不要：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path tests"
```
インストーラー、アンインストーラー、ネットワーク、レジストリはすべてモックです：テストが PC に触れることはありません。

## トラブルシューティング

- **ゲームが前の言語のまま**：書き換え中に Riot Client がまだ動いていました。ランチャーは自動で終了させますが、
  プロセスが固まっている場合は手動で終了（通知領域のアイコン → 終了）して再試行してください。
- **ダブルクリックしても何も起きない**：フォルダーで PowerShell を開き、`.\app\launch-lol.ps1 -Locale ja_JP` を実行して
  エラーを確認してください（設定ファイルが見つからない、パスが間違っているなど）。
- **スプラッシュやダイアログの文字化け**（`Ã©`、`â€¦`）：`.ps1` が BOM なしで保存し直されています。
  すべてのスクリプト（`launch-lol.ps1`、`manage-companion-app.ps1`、`create-shortcuts.ps1`、`lib\*.ps1`）は
  **BOM 付き UTF-8** である必要があります（VS Code：ステータスバー → エンコード → 「エンコード付きで保存」）。
- **ショートカットのアイコンが更新されない**：Windows のアイコンキャッシュです。フォルダーで右クリック → 最新の情報に更新、
  それでもだめならサインアウト／サインインしてください。
- **「Ne pas exécuter en tant qu'administrateur」**：`install.bat` を昇格して起動しました。通常起動してください。
- **「winget indisponible」**：この Windows に App Installer がありません。Microsoft Store からインストールするか、
  ツールがブラウザーで開く Blitz のダウンロードページを使ってください。
- **「désinstalleur … non signé」**：レジストリで見つかったアンインストーラーが想定した発行者の署名ではありません。
  ツールはそれを実行しません。Windows の「インストールされているアプリ」からアンインストールしてください。
- **「Désinstaller」の後も補助アプリが残っている**：発行者のダイアログを確認せずに閉じた（Overwolf）か、
  アンインストールに予想以上の時間がかかりました。他には何もインストールされていません。`install.bat` を再実行してください。
- **ゲームを起動せずにテストする**：`.\app\launch-lol.ps1 -Locale ja_JP -DryRun -YamlPath copy.yaml` で、何も終了・起動せずに
  スプラッシュを表示してコピーを書き換えます。`app\manage-companion-app.ps1 -DryRun` は補助アプリの操作を実行せずに表示します。
