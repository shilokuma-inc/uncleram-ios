# CLAUDE.md

このファイルは、このリポジトリで作業する Claude Code（ほかの AI エージェントを含む）への指示です。

## プロジェクト

**Uncle RAM**（アンクル・ラム、Bundle ID `jp.shilokuma.UncleRAM`）は、端末の本物のメモリを「献上」する長押しワンボタンの押し引きゲーム。iPhone・iPad・Mac を 1 つのターゲットで作る。
長押ししている間だけメモリを確保し、離すと「納品」。隠れた「回収ライン」を越えると、そのラウンドの献上分はすべて失う。安全ラインで必ず止めるので、OS による強制終了（jetsam）は起こさない。

## 資料

仕様の正は [docs/SPEC.md](docs/SPEC.md)。食い違うときは「ゲーム性の見直し」「説明なしで分かる UI」の節を最優先にし、次に「実装の詳細」の節を優先する。
決定事項・数値の初期値・段取りの要点は [docs/HANDOFF.md](docs/HANDOFF.md)。画面は [docs/design/](docs/design/) の画像に合わせる（iPhone は 390 × 844、Mac は 1200 × 760 の 2 倍）。
仕様で決まっていない点に当たったら、推測で埋めずにユーザーに聞く。

引き継ぎ資料（UncleRAM-handoff）とリポジトリの置き場所の対応:

| 引き継ぎ資料 | リポジトリ |
| --- | --- |
| `START_HERE.md`・`HANDOFF.md`・`SPEC.md` | `docs/`（公開リポジトリのため、元ネタの実在の人物・企業の名前とリンクは伏せた） |
| `design/png/` | `docs/design/` |
| `tools/sim.py` | `Tools/sim.py`（macOS のファイルシステムは大文字と小文字を区別しないので、テンプレートの `Tools/` と同じ場所になる） |
| `tools/process.py`・`flagg.py`・`airship.py` | `Tools/artwork/`（PIL を使う。素材の作り直し用） |
| `assets/images/`・`assets/icon/` | アセットカタログ |
| `design/*.html`・`review/`・`mock/`・`assets/source/` | 入れていない（開発する PC の `~/Desktop/ios/UncleRAM-handoff/` に残す） |

`mock/` の Web モックは、ゲーム性を見直す前の古いルールで動いている。遊び心地の目安にとどめ、数値と流れは SPEC.md に従う。

## 守ること

- **安全:** 確保のたびに安全ラインの 2 つの条件（献上量＋確保量 ≤ 枠 × 85%、今の残量 − 確保量 ≥ max(枠 × 15%, 200MB)）を必ず確かめる。`Allocator` 以外からメモリを確保しない。演出の前に全メモリを解放する
- **審査:** 回収演出は OS の画面（アラート・ホーム画面・クラッシュ画面・ステータスバー）に似せない。「端末が速くなる」と読める表現を入れない。実在の人物・企業・ロゴ（Apple のロゴや製品画像を含む）を出さない
- **名前:** アプリの中にも、ストアの説明にも、コミットや PR にも、元ネタになった実在の人物の名前を出さない
- **ランキング:** 課金・強化・保険が効くモード（定期便）はランキングに入れない
- **見た目:** ライトモード固定（アイコンだけダーク版あり）。色と書体は HANDOFF.md の「デザインの実装メモ」のとおり

## ユーザーが決めたこと（仕様書に無いもの）

- 2026-11-12: リポジトリは shilokuma-inc の public。仕様書は実在の名前を伏せて `docs/` に入れる
- 2026-11-12: iPhone は縦だけ。iPad は全方向（Split View のため）で、横幅で切り替える（広いときは Mac の横長レイアウト、狭いときは iPhone のレイアウト）
- 2026-11-23: 年末年始の審査の混雑は承知のうえで、初回は全部入り（HANDOFF.md「確定した決定事項」の初回の範囲）で出す。範囲を絞って先に出す案は取らない
- 2026-11-23: Mac で圧縮が急に増えたら「監査」にする閾値は、0.5 秒の間に max(枠の 5%, 256MB)
- 2026-11-23: 枠が 600MB 未満のときの案内は「いまは空きメモリが足りません」と「枠 ○○ MB。ほかのアプリを閉じてから、もう一度お試しください。」
- 2026-11-23: はったりの「にやり」は、毎回、会長の台詞を 0.8 秒だけ「……なんてな。」にして見せる（表情の絵は足さない）。SPEC.md の「初めてのときだけの吹き出し『…なんてな』」は、ほかの吹き出しと一緒に入れる
- 2026-11-23: 警告（3 段階目）の会長の台詞は接近と同じにし、警告は画面のノイズ（と振動）で知らせる
- 2026-11-23: 確保したメモリへの書き込み方は、ページごとに少しだけ乱数を書く方式（sparse）にする。経緯と計測の結果は [docs/SPEC.md](docs/SPEC.md)「書き込み方の見直し」
- 2026-11-24: 試作の合格条件の対象から、枠の小さい iPhone とメモリの大きい iPad を外す（手元に端末がないため）。試作は標準的な iPhone（iPhone 13 で合格済み）と Mac で見る。公開前の実機での確認は変えない
- 2026-11-24: Game Center のランキング 14 本の名前と数値は、SPEC.md「Game Center と名前の扱い」のとおり。設定は `UncleRAM/GameCenterResources.gamekit` に書き、Xcode から App Store Connect に送る。実績は段取り 4 で称号と一緒に作る
- 2026-11-24: 試作の Mac の条件は、Mac mini（8GB）の結果で合格にする。メモリの大きい Mac で解放が 200ms に収まるかは、公開前の実機での確認で見る（越えたら、枠の上限を下げるか Mac の条件を見直す）
- 2026-11-26: Dynamic Type は「さらに大きな文字」を使わない範囲（xxxLarge）まで。ラウンドはスクロールさせずに 1 画面に収める。App Store の「大きな文字」の表記は出さない
- 2026-11-26: デイリーの通し番号の起点（#1）は、公開日が決まるまで仮に 2026-12-01（世界標準時）にする。公開日が決まったら直す（HANDOFF.md の段取り 5）
- 2026-11-26: タイトル画面には、行き先の画面があるリンクとボタンだけを出す（強化・定期便・取引先は段取り 4、ランキングは画面ができたら、デイリーはつなぐときに足す）。結果の画面に「タイトルへ」の文字のリンクを足す（ラウンドの途中には置かない）。搭載メモリへの会長の一言は 2 段階（ランキングのメモリのクラスでいちばん小さいときは「……まあ、いいでしょう」、それより大きいときは「上客様がお見えです」）
- 2026-11-26: 初回の案内の文言は、見出し「ご提供の前に」、本文「このゲームは、端末の本物のメモリを確保して遊びます。」「献上している間、裏で開いているアプリが終了することがあります。」「端末が速くなるアプリではありません。」、ボタン「承知しました」

## 進め方

段取りは HANDOFF.md の「段取り（マイルストーン）」。試作の合格条件（段取り 2）は 2026-11-24 に満たした。今は段取り 3（速達便が遊べる版）。

## 環境

- Xcode 26.6 / iOS・iPadOS 18.0 以上・macOS 15.0 以上（Mac Catalyst ではなく macOS そのもの）
- SwiftUI のマルチプラットフォームの 1 ターゲット（`SDKROOT = auto`、`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`）。Mac は App Sandbox を有効にする
- Swift 6（言語モード 6・Strict Concurrency complete・既定の分離は MainActor。UI テストのターゲットだけ nonisolated）
- Swift Testing（Unit）/ XCTest（UI テスト）/ SwiftLint 0.65.1（Build Tool Plugin と CI の `--strict`）

## ビルド・テスト

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer   # xcode-select が別の Xcode のとき
# iOS Simulator（名前ではなく UDID で指定する。xcrun simctl list devices available）
xcodebuild test -project UncleRAM.xcodeproj -scheme UncleRAM \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath <リポジトリの外> \
  -skipPackagePluginValidation -skipMacroValidation -parallel-testing-enabled NO
# Unit テストだけ: -only-testing:UncleRAMTests を足す
# macOS（CI と同じアドホック署名。テストのときだけ App Sandbox を無効にする）
xcodebuild test -project UncleRAM.xcodeproj -scheme UncleRAM -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath <リポジトリの外> -skipPackagePluginValidation -skipMacroValidation \
  -skip-testing:UncleRAMUITests -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_APP_SANDBOX=NO
# SwiftLint（CI と同じ。SPM が解決したバイナリを使う）
"$(find <DerivedData>/SourcePackages/artifacts -type f -name swiftlint -path '*macos*' | head -1)" lint --strict
# 数値の試算（早期回収・ヒント・速さを変えたら回し直す。1 分ほどかかる）
python3 Tools/sim.py
# 書体（文言に新しい漢字などが増えたら、日本語の書体を作り直す。CI は --check で回し忘れを止める）
uv run Tools/fonts/subset.py
# 試作の計測（ラウンドを自動で続けて、解放の時間・落ちたフレーム・使用量・スワップを JSON に残す）
<アプリ> -bench 100   # 書き込み方は既定で本番と同じ sparse。-bench-fill full で全体を乱数で埋める方式と比べられる
# 撮影モード（メモリを確保せずに、ラウンドの場面を表示する。PR のスクリーンショット用）
<アプリ> -screenshot-demo -screenshot-scene approach   # ほかの場面: home・sign・warning・delivered・collected
```

- Simulator の `os_proc_available_memory()` は実際の値を返さないので、仮の枠（例: 2GB）で動かす（SPEC.md「技術仕様」）

## ブランチ運用

- ベースブランチは `develop`。作業ブランチは `feat/issue-<番号>-<内容>` などで切り、PR は `develop` 宛てにする
- コミットは `[type] メッセージ`（日本語）、PR のタイトルは `【TYPE】タイトル`。マージは merge commit（Squash しない）
- リポジトリだけの知見は [LEARNINGS.md](LEARNINGS.md) に書く
