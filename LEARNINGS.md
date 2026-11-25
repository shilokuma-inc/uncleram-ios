# LEARNINGS — uncleram-ios の知見

このリポジトリだけで通じる知見を溜める（全リポジトリ共通の知見は `~/.agents/LEARNINGS.md`）。

- 1 項目 = 1 つの箇条書き。見出しの下に追記し、日付（YYYY-MM-DD）を添える
- コードや git の履歴を読めば分かることは書かない。PC 固有の値（ローカルパス・Simulator の UDID）と秘密情報は書かない
- 古くなった項目は消すか直す

## プロジェクトの設定

- `INFOPLIST_KEY_UIApplicationSupportsMultipleScenes` は Info.plist の生成に使われない。`INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES` のままだと、Info.plist のファイルに `UIApplicationSupportsMultipleScenes = false` を書いても `true` で上書きされる。生成を止めて、`UIApplicationSceneManifest` をファイルに書く（2026-11-12）
- 引き継ぎ資料の `tools/` は、macOS のファイルシステムが大文字と小文字を区別しないため、テンプレートの `Tools/` と同じ場所になる。`Tools/sim.py` と `Tools/artwork/` に置いた（2026-11-12）
- プロジェクトは Xcode 26.6 に合わせている。Xcode 27.1 で開いて GameKit バンドルの Push を試したあと、`project.pbxproj` と `Info.plist` が書き換わっていた。並び順が変わり、`UncleRAM.entitlements` が同期フォルダの除外から外れ、`ITSAppUsesNonExemptEncryption` が Info.plist から `INFOPLIST_KEY_` の設定に移り、`Configs/Project.xcconfig` にある `DEVELOPMENT_TEAM` が重ねて書かれる。これはコミットしない（2026-11-26）

## テスト

- リポジトリが `~/Desktop` の下にあると、Mac の Unit テストからソースのファイル（`#filePath` から辿ったもの）を読もうとしたところで、テストが止まって進まなくなる。テストを動かすアプリ（test host）が、デスクトップのファイルへのアクセスの許可を待つため（アドホック署名はビルドのたびに別のアプリとみなされる）。CI はデスクトップの外に checkout するので止まらない。ソースを読む確かめは、テストではなく CI のスクリプト（例: `Tools/fonts/subset.py --check`）で行う（2026-11-26）

## Game Center

- Xcode 26 の GameKit バンドル（`.gamekit`）は、中の `gameCenterResources.json`（`meta.version` は `2024-11-15`）だけで読める。書き方は Apple の公式サンプル（apple/unityplugins の `Apple.GameKit.Sample/GameCenterResources.gamekit`）が参考になる。繰り返し型は `recurrenceStartDate`（UTC の ISO 8601）・`recurrenceDuration`（例 `P1D`）・`recurrenceRule`（例 `FREQ=DAILY;INTERVAL=1`）、スコアの範囲は文字列（`"0"`・`"300"`）（2026-11-24）
- 同期フォルダ（`PBXFileSystemSynchronizedRootGroup`）に置いた `.gamekit` は、xcodebuild ではフォルダとして扱われ、中の JSON がアプリの直下にコピーされる。動きには影響しない。Xcode で作られたほかのプロジェクトでも、同期フォルダの中に置いてターゲットに入れている（2026-11-24）
- Mac でアドホック署名（`CODE_SIGN_IDENTITY=-`・`CODE_SIGN_STYLE=Manual`・プロファイルなし）すると、`com.apple.developer.game-center` の権限があるだけで「requires a provisioning profile」でビルドが止まる。CI の Mac のテストとアーカイブはアドホック署名なので、権限は今は iOS だけ（`CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]`・`[sdk=iphonesimulator*]`）に付けている（2026-11-24）
- 「Push to App Store Connect」をすると、Xcode が `gameCenterResources.json` を自分の書き方（キーの並び・`/` を `\/` にする）で書き直す。中身は変わらない。差分が出ないよう、リポジトリの JSON は Xcode の書き方にそろえてある。手で直したあとに Push すると、また書き直されるので、Push のあとの差分もコミットする（2026-11-26）

## 仕様と試算

- 引き継ぎの `Tools/sim.py` は、警告（3 段階目）を「手前 3%・±1.5」で試算していた。SPEC.md の値（手前 2%・±2%）で回すと、SPEC.md の試算の表（警告で離す: 期待値 87・回収 54%）が再現するので、SPEC.md の値に合わせた。仕様の数値を変えたら、表と sim.py の両方を見直す（2026-11-12）

## 計測（試作の合格条件）

- 計測は起動引数 `-bench <ラウンド数> -bench-fill full|sparse` か、Debug・TestFlight のビルドの画面右上の「計測」。Mac の結果は `~/Library/Containers/jp.shilokuma.UncleRAM/Data/Documents/bench-*.json` に残る（2026-11-12）
- 計測中に同じ Mac でビルドや Simulator を動かすと、落ちたフレームと解放の時間が乱れる。計測の間は重い処理を止める。社用の Mac は、それでも回ごとのばらつきが大きかった（落ちたフレーム 0.1〜0.5%）（2026-11-12）
- `os_proc_available_memory()` は macOS では使えない（unavailable）。iOS の量り方は `#if os(iOS)` で囲む（2026-11-12）
- 実機の計測の結果は、Mac からケーブルで取り出せる。`xcrun devicectl device info files --device <UDID> --domain-type appDataContainer --domain-identifier jp.shilokuma.UncleRAM --subdirectory Documents` で一覧し、`xcrun devicectl device copy from …（同じ指定）--source Documents/<ファイル名> --destination <保存先>` でコピーする（2026-11-23）
- Xcode（xcodebuild）から実機に入れた Release ビルドでも、画面の「計測」ボタンは出た（`AppTransaction` の environment が production にならないため）。計測は実際の速さに近い Release で行う（2026-11-23、iPhone 13）
- 社用の Mac は負荷が高すぎて、Mac の計測に使えない（2026-11-23 は load average 5〜8 で解放が 11/11 の 3.5 倍遅く、11/24 は 400 を越えていた）。空いている Mac は無いので、AskHub の司令塔が動いている Mac mini（`ssh macmini`、画面にログインしたまま）で測る。再起動を頼み、負荷が 3 未満に落ちるのを待つ（再起動の直後は写真の解析などで 20〜30 になり、15 分ほどで落ち着いた）。AskHub は止めなくても測れた（2026-11-24）
- 別の Mac で測るときは、この Mac で Release をアドホック署名でビルドし（CLAUDE.md の macOS のテストと同じ署名の引数で、`ENABLE_APP_SANDBOX` は上書きしない）、`tar czf - UncleRAM.app | ssh <host> 'tar xzf -'` で送って `open -n <app> --args -bench 100` で起動する。scp や tar で送ったものは quarantine が付かないので、そのまま起動できる。スリープは `caffeinate -dimsu -t <秒>` で止め、裏の音は `afplay` で流して、終わりにプロセスが残っているかで確かめる（2026-11-24）
- 解放が遅いとき、アプリのせいか Mac のせいかを切り分けるには、アプリの外で同じやり方（16MB ずつ mmap し、ページごとに 16 バイトの乱数を書いて、munmap の時間だけを量る。Swift で 30 行ほど、`swiftc -O`）の小さなプログラムを、計測の前後に流す。Mac mini では 1GB あたり 8〜14ms、アプリの中の munmap は 23ms だった（2026-11-24）
- Mac はウィンドウ 1 つだけの `Window` シーンなので、ウィンドウを閉じるとアプリごと終了する。計測中に閉じると、確保したメモリはプロセスの終了で回収されるが、途中までの計測の JSON は残らない（2026-11-23）
- 計測の JSON の `releaseMilliseconds` は、2026-11-23 から「終わりが決まってから全解放が終わるまで（確保を止めるのを待つ時間を含む）」になった。それより前の JSON（2026-11-11 の Mac の結果など）は munmap だけの時間なので、そのまま比べない。今の munmap だけの時間は `unmapMilliseconds`（2026-11-23）
- Mac のアプリを Bash から起動して `screencapture -l` で撮るとき、前の起動のウィンドウの状態が残っていると、テンプレートの WindowGroup の版はウィンドウを開かないことがある。`-ApplePersistenceIgnoreState YES` を付けると開いた。ただし `Window` シーンの版では、この引数を付けるとウィンドウが開かなかったので付けない（2026-11-12）

