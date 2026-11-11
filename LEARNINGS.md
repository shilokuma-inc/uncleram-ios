# LEARNINGS — uncleram-ios の知見

このリポジトリだけで通じる知見を溜める（全リポジトリ共通の知見は `~/.agents/LEARNINGS.md`）。

- 1 項目 = 1 つの箇条書き。見出しの下に追記し、日付（YYYY-MM-DD）を添える
- コードや git の履歴を読めば分かることは書かない。PC 固有の値（ローカルパス・Simulator の UDID）と秘密情報は書かない
- 古くなった項目は消すか直す

## プロジェクトの設定

- `INFOPLIST_KEY_UIApplicationSupportsMultipleScenes` は Info.plist の生成に使われない。`INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES` のままだと、Info.plist のファイルに `UIApplicationSupportsMultipleScenes = false` を書いても `true` で上書きされる。生成を止めて、`UIApplicationSceneManifest` をファイルに書く（2026-11-12）
- 引き継ぎ資料の `tools/` は、macOS のファイルシステムが大文字と小文字を区別しないため、テンプレートの `Tools/` と同じ場所になる。`Tools/sim.py` と `Tools/artwork/` に置いた（2026-11-12）

## 仕様と試算

- 引き継ぎの `Tools/sim.py` は、警告（3 段階目）を「手前 3%・±1.5」で試算していた。SPEC.md の値（手前 2%・±2%）で回すと、SPEC.md の試算の表（警告で離す: 期待値 87・回収 54%）が再現するので、SPEC.md の値に合わせた。仕様の数値を変えたら、表と sim.py の両方を見直す（2026-11-12）

## 計測（試作の合格条件）

- 計測は起動引数 `-bench <ラウンド数> -bench-fill full|sparse` か、Debug・TestFlight のビルドの画面右上の「計測」。Mac の結果は `~/Library/Containers/jp.shilokuma.UncleRAM/Data/Documents/bench-*.json` に残る（2026-11-12）
- 計測中に同じ Mac でビルドや Simulator を動かすと、落ちたフレームと解放の時間が乱れる。計測の間は重い処理を止める。社用の Mac は、それでも回ごとのばらつきが大きかった（落ちたフレーム 0.1〜0.5%）（2026-11-12）
- `os_proc_available_memory()` は macOS では使えない（unavailable）。iOS の量り方は `#if os(iOS)` で囲む（2026-11-12）
- Mac のアプリを Bash から起動して `screencapture -l` で撮るとき、前の起動のウィンドウの状態が残っていると、テンプレートの WindowGroup の版はウィンドウを開かないことがある。`-ApplePersistenceIgnoreState YES` を付けると開いた。ただし `Window` シーンの版では、この引数を付けるとウィンドウが開かなかったので付けない（2026-11-12）

