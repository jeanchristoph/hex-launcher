# LoL Lang Switcher

[English](README.md) · [Français](README.fr.md) · **日本語**

デスクトップのショートカットから、好きな言語（日本語、フランス語など）で League of Legends を起動します。
小さなアニメーション付きスプラッシュを表示し、黒いコンソール画面は出ません。
起動後に補助アプリ（Porofessor、Blitz、OP.GG など）を自動で立ち上げることもできます。

## フォルダーの内容

| ファイル | 役割 |
|---|---|
| `install.bat` | **これをダブルクリック**：インストール場所を検出し、`config.json` を生成し、デスクトップにショートカットを作成 |
| `config.json` | Riot のパスと補助アプリの設定。`install.bat` が生成。検出がうまくいかない場合は手動編集可 |
| `locales.json` | インストール時に選べる言語のカタログ（Riot のコード＋表示名） |
| `launch-lol.ps1` | ランチャー本体：Riot Client を終了し、言語を強制設定し、ゲームを再起動（＋補助アプリ） |
| `detect-config.ps1` | `install.bat` から呼ばれる：Riot と補助アプリ（Porofessor、Blitz、OP.GG）を検出 |
| `create-shortcuts.ps1` | `install.bat` から呼ばれる：言語選択ダイアログを表示し、言語ごとに `.lnk` をデスクトップに作成（デスクトップに書き込めない場合はこのフォルダーに作成） |
| `make-flag-icons.ps1` | ツール：Riot のアイコンから `ico/` の国旗アイコンを再生成（通常の使用には不要） |
| `ico/` | アイコン：Riot のオリジナル＋言語ごとの国旗バージョン（`league-of-legends-xx.ico`） |

`League of Legends XX` ショートカット（選択した言語ごとに 1 つ）は `install.bat` がデスクトップに作成します。

## 新しい PC へのインストール

1. このフォルダーを好きな場所にコピーします（例：`Documents\scripts\lol`）。別の PC から持ってきた場合は、
   検出が正しく動くように **`config.json` を含めない**でください。
2. **`install.bat`** をダブルクリックします。以下を行います：
   - Riot Client を検出（Riot 公式のファイル `RiotClientInstalls.json` を使用）し、Porofessor（Overwolf）、
     Blitz、OP.GG のうち最初に見つかった補助アプリを検出（なければ「なし」）；
   - `config.json` を書き出し（既に存在する場合は上書きしません：手動設定は保持されます）；
   - **ダイアログ**を表示：使いたい言語にチェック（初回は JP と FR が選択済み、2 回目以降は既にインストール済みの言語）
     して「Installer」をクリック；
   - チェックした言語ごとに `League of Legends XX` ショートカットをデスクトップに作成し、チェックを外した言語の
     ショートカットを削除（変更がなくても必須：`.lnk` には絶対パスが埋め込まれています）。
     デスクトップに書き込めない場合（保護されたフォルダー、OneDrive など）は、代わりにこのフォルダーに作成します。
3. 使いたい言語のショートカットをダブルクリックします。

後から言語を追加・削除するには：`install.bat` を再実行してチェックを変更してください。

検出が間違っていたり、別のアプリを使う場合は：`config.json` を編集（下記参照）して `install.bat` を再実行。
検出をやり直すには：`config.json` を削除して再実行してください。

新しい言語で初めて起動するとき、Riot Client がテキスト＋ボイスパック（数百 MB）をダウンロードします。正常な動作です。

## `config.json`

```json
{
  "riotClientPath": "C:\\Riot Games\\Riot Client\\RiotClientServices.exe",
  "productSettingsPath": "C:\\ProgramData\\Riot Games\\Metadata\\league_of_legends.live\\league_of_legends.live.product_settings.yaml",
  "companionApp": {
    "enabled": true,
    "name": "Porofessor",
    "path": "C:\\Program Files (x86)\\Overwolf\\OverwolfLauncher.exe",
    "arguments": "-launchapp pibhbkkgefgheeglaeemkkfjlhidhcedalapdggh -from-startmenu"
  }
}
```

バックスラッシュは二重（`\\`）にしてください — JSON のためです。

| キー | 説明 |
|---|---|
| `riotClientPath` | `RiotClientServices.exe` のパス。既定は `C:\Riot Games\Riot Client\`。 |
| `productSettingsPath` | Riot が LoL の言語を保存する yaml ファイル。特殊なインストールでない限り `C:\ProgramData\Riot Games\Metadata\…` 配下。 |
| `companionApp.enabled` | ゲームの後にアプリを起動するなら `true`、起動しないなら `false`。 |
| `companionApp.name` | スプラッシュに表示される名前。見た目のみ。 |
| `companionApp.path` | 起動する実行ファイル。 |
| `companionApp.arguments` | 起動引数。なければ空文字 `""`。 |

`path` がこの PC に存在しない場合、ランチャーはそれをスキップしてスプラッシュに警告を表示します — ゲームは起動します。

### 補助アプリの例

**なし**：
```json
"companionApp": { "enabled": false }
```

**Porofessor**（Overwolf 経由）— 上記の既定設定。

**Blitz**：
```json
"companionApp": {
  "enabled": true,
  "name": "Blitz",
  "path": "C:\\Users\\<ユーザー名>\\AppData\\Local\\Programs\\Blitz\\Blitz.exe",
  "arguments": ""
}
```

**その他の Overwolf アプリ**：`OverwolfLauncher.exe` はそのままに、`-launchapp` の後の識別子を置き換えます
（アプリがスタートメニューに作成したショートカットのプロパティで確認できます）。

**アプリを自動検出の対象にする**：`detect-config.ps1` の `$CompanionCandidates` にエントリ（名前、パス、引数）を追加します。
リストの順序が優先順位です。

## 言語

Riot が提供するすべての言語が `locales.json` にあり、インストール時に選択できます。ショートカット名は
`League of Legends XX`（XX = コードの国部分：`ja_JP` → JP、`ko_KR` → KR）です。

アイコン：`ico/league-of-legends-xx.ico`（xx は小文字）— カタログ内のすべての言語に国旗があります。
アイコンがない場合は Riot のオリジナルアイコンが使われます。

カタログにない言語（Riot の新しいロケール）を追加するには：
1. yaml ファイルの `available_locales` にある正確なコードで `locales.json` に 1 行追加；
2. （任意）`make-flag-icons.ps1` の `$FlagDrawings` に国旗の描画を追加し、
   `powershell -NoProfile -ExecutionPolicy Bypass -File make-flag-icons.ps1 -Locales xx_XX` を実行。

ダイアログなしで使う場合（スクリプト、配布）：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File create-shortcuts.ps1 -Locales ja_JP,ko_KR
```

## 仕組み

Riot Client の「言語」設定はランチャーの言語を変えるだけで、ゲームの言語は変わりません。LoL の言語は
`product_settings.yaml` の `settings.locale` から読み込まれ、Riot Client は終了するたびにこのファイルを書き直します。
そのためランチャーは次の順序で処理します：

1. Riot Client と LoL クライアントが起動していれば終了する（そうしないと変更が上書きされます）。
2. `settings.locale` を指定の言語に書き換える（Riot が管理する `default_locale` は変更しません）。
3. 念のため `--locale=xx_XX` を付けて Riot Client を起動する。
4. 有効なら補助アプリを起動する。

## トラブルシューティング

- **ゲームが前の言語のまま**：書き換え中に Riot Client がまだ動いていました。ランチャーは自動で終了させますが、
  プロセスが固まっている場合は手動で終了（通知領域のアイコン → 終了）して再試行してください。
- **ダブルクリックしても何も起きない**：フォルダーで PowerShell を開き、`.\launch-lol.ps1 -Locale ja_JP` を実行して
  エラーを確認してください（設定ファイルが見つからない、パスが間違っているなど）。
- **スプラッシュの文字化け**（`Ã©`、`â€¦`）：`launch-lol.ps1` が BOM なしで保存し直されています。
  **BOM 付き UTF-8** である必要があります（VS Code：ステータスバー → エンコード → 「エンコード付きで保存」）。
- **ショートカットのアイコンが更新されない**：Windows のアイコンキャッシュです。フォルダーで右クリック → 最新の情報に更新、
  それでもだめならサインアウト／サインインしてください。
- **ゲームを起動せずにテストする**：`.\launch-lol.ps1 -Locale ja_JP -DryRun -YamlPath copy.yaml` で、何も終了・起動せずに
  スプラッシュを表示してコピーを書き換えます。
