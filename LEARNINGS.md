# LEARNINGS — uncleram-ios の知見

このリポジトリだけで通じる知見を溜める（全リポジトリ共通の知見は `~/.agents/LEARNINGS.md`）。

- 1 項目 = 1 つの箇条書き。見出しの下に追記し、日付（YYYY-MM-DD）を添える
- コードや git の履歴を読めば分かることは書かない。PC 固有の値（ローカルパス・Simulator の UDID）と秘密情報は書かない
- 古くなった項目は消すか直す

## プロジェクトの設定

- `INFOPLIST_KEY_UIApplicationSupportsMultipleScenes` は Info.plist の生成に使われない。`INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES` のままだと、Info.plist のファイルに `UIApplicationSupportsMultipleScenes = false` を書いても `true` で上書きされる。生成を止めて、`UIApplicationSceneManifest` をファイルに書く（2026-11-12）
- 引き継ぎ資料の `tools/` は、macOS のファイルシステムが大文字と小文字を区別しないため、テンプレートの `Tools/` と同じ場所になる。`Tools/sim.py` と `Tools/artwork/` に置いた（2026-11-12）
