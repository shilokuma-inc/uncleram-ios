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

## 進め方

段取りは HANDOFF.md の「段取り（マイルストーン）」。**試作の合格条件（段取り 2）を満たすまでは、ほかの機能に手を広げない。**

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
# 数値の試算（早期回収・ヒント・速さを変えたら回し直す）
python3 Tools/sim.py
```

- Simulator の `os_proc_available_memory()` は実際の値を返さないので、仮の枠（例: 2GB）で動かす（SPEC.md「技術仕様」）

## ブランチ運用

- ベースブランチは `develop`。作業ブランチは `feat/issue-<番号>-<内容>` などで切り、PR は `develop` 宛てにする
- コミットは `[type] メッセージ`（日本語）、PR のタイトルは `【TYPE】タイトル`。マージは merge commit（Squash しない）
- リポジトリだけの知見は [LEARNINGS.md](LEARNINGS.md) に書く
