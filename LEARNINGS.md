# LEARNINGS — uncleram-ios の知見

このリポジトリだけで通じる知見を溜める（全リポジトリ共通の知見は `~/.agents/LEARNINGS.md`）。

- 1 項目 = 1 つの箇条書き。見出しの下に追記し、日付（YYYY-MM-DD）を添える
- コードや git の履歴を読めば分かることは書かない。PC 固有の値（ローカルパス・Simulator の UDID）と秘密情報は書かない
- 古くなった項目は消すか直す

## プロジェクトの設定

- `INFOPLIST_KEY_UIApplicationSupportsMultipleScenes` は Info.plist の生成に使われない。`INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES` のままだと、Info.plist のファイルに `UIApplicationSupportsMultipleScenes = false` を書いても `true` で上書きされる。生成を止めて、`UIApplicationSceneManifest` をファイルに書く（2026-11-12）
- 引き継ぎ資料の `tools/` は、macOS のファイルシステムが大文字と小文字を区別しないため、テンプレートの `Tools/` と同じ場所になる。`Tools/sim.py` と `Tools/artwork/` に置いた（2026-11-12）
- Xcode の画面でプロジェクトを開くと、26.6 でも `project.pbxproj` を Xcode の並び順に書き直し、同期フォルダの除外から `UncleRAM.entitlements` を外す。権限のファイルは除外しなくてもアプリに入らない（ビルドして確かめた）ので、2026-11-26 にリポジトリを Xcode の形にそろえた。手で pbxproj を直したら、Xcode で開いて保存された形でコミットする。Xcode 27.1 で開いて GameKit バンドルの Push を試したあとは、さらに `ITSAppUsesNonExemptEncryption` が Info.plist から `INFOPLIST_KEY_` の設定に移り、`Configs/Project.xcconfig` にある `DEVELOPMENT_TEAM` が pbxproj に重ねて書かれていた。こちらはコミットしない（2026-11-26）

## テスト

- リポジトリが `~/Desktop` の下にあると、Mac の Unit テストからソースのファイル（`#filePath` から辿ったもの）を読もうとしたところで、テストが止まって進まなくなる。テストを動かすアプリ（test host）が、デスクトップのファイルへのアクセスの許可を待つため（アドホック署名はビルドのたびに別のアプリとみなされる）。CI はデスクトップの外に checkout するので止まらない。ソースを読む確かめは、テストではなく CI のスクリプト（例: `Tools/fonts/subset.py --check`）で行う（2026-11-26）

- シェア画像（献上明細書）を目で確かめるときは、`TEST_RUNNER_UNCLERAM_SHARE_IMAGE_DIR=<リポジトリの外のフォルダ>` を付けて `-only-testing:UncleRAMTests/ShareTests` を流す。xcodebuild は `TEST_RUNNER_` を外した名前でテストに環境変数を渡すので、4:5 と 9:16 の PNG（納品と回収）がそのフォルダに書き出される。Mac と iOS Simulator のどちらでも書き出せる（2026-11-26）

- リプレイ動画を目で確かめるときは、`TEST_RUNNER_UNCLERAM_REPLAY_VIDEO_DIR=<リポジトリの外のフォルダ>` を付けて `-only-testing:UncleRAMTests/ReplayTests` を流す。速達便の納品・回収とデイリーの回収の mp4（約 10 秒）と、何コマかの PNG（AVAssetImageGenerator で取り出したもの）が書き出される。Swift Testing の 1 つのテストだけを流すときは `-only-testing:'UncleRAMTests/ReplayTests/exportedVideoHasExpectedFormat()'` のように `()` まで付ける（付けないと 0 件で成功になる）（2026-11-26）

- CI の Build は、作業ブランチへの push では Unit テストだけを流し、PR では iOS Simulator の UI テストまで流す。画面の流れを変えたら、手元で `-only-testing:UncleRAMUITests/UncleRAMUITests` を流しておく。UI テストは起動引数 `-hasAcknowledgedSafetyNotice YES`（UserDefaults の引数のドメイン）で、初回の案内を飛ばしている（2026-11-26）

## Game Center

- UI テストでは、起動引数 `-disableGameCenter YES` で Game Center のサインインを始めない。最初のラウンドを終えるとサインインを始めるので、Simulator で Game Center のサインインの画面が出て、UI テストの流れが止まるため（2026-11-26）

- Xcode 26 の GameKit バンドル（`.gamekit`）は、中の `gameCenterResources.json`（`meta.version` は `2024-11-15`）だけで読める。書き方は Apple の公式サンプル（apple/unityplugins の `Apple.GameKit.Sample/GameCenterResources.gamekit`）が参考になる。繰り返し型は `recurrenceStartDate`（UTC の ISO 8601）・`recurrenceDuration`（例 `P1D`）・`recurrenceRule`（例 `FREQ=DAILY;INTERVAL=1`）、スコアの範囲は文字列（`"0"`・`"300"`）（2026-11-24）
- 同期フォルダ（`PBXFileSystemSynchronizedRootGroup`）に置いた `.gamekit` は、xcodebuild ではフォルダとして扱われ、中の JSON がアプリの直下にコピーされる。動きには影響しない。Xcode で作られたほかのプロジェクトでも、同期フォルダの中に置いてターゲットに入れている（2026-11-24）
- Mac でアドホック署名（`CODE_SIGN_IDENTITY=-`・`CODE_SIGN_STYLE=Manual`・プロファイルなし）すると、`com.apple.developer.game-center` の権限があるだけで「requires a provisioning profile」でビルドが止まる。CI の Mac のテストとアーカイブはアドホック署名なので、権限は iOS だけ（`CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]`・`[sdk=iphonesimulator*]`）に付け、Mac はアーカイブのあとで `codesign -d --entitlements - --xml` で今の権限を取り出し、`PlistBuddy -c "Merge UncleRAM/UncleRAM.entitlements"` で足して、`codesign --force --sign - --entitlements … --preserve-metadata=identifier,flags,runtime` で署名し直す（codesign そのものはプロファイルを確かめない）。Export はこの権限を引き継ぐ（2026-11-26）
- 「Push to App Store Connect」をすると、Xcode が `gameCenterResources.json` を自分の書き方（キーの並び・`/` を `\/` にする）で書き直す。中身は変わらない。差分が出ないよう、リポジトリの JSON は Xcode の書き方にそろえてある。手で直したあとに Push すると、また書き直されるので、Push のあとの差分もコミットする（2026-11-26）

## 音

- afconvert で作った AAC（`.m4a`）は、エンコーダーの頭の遅れ（priming 2112 フレーム）と終わりの余り（remainder）を持つ。AVAudioFile でデコードすると元の長さとフレーム数まで一致し、AVAudioPlayer の `numberOfLoops = -1` でも継ぎ目が出ない。ループさせる音（BGM を含む）も AAC でよい。`afinfo` の「valid frames + priming + remainder」で確かめられる（2026-11-26）
- AVAudioPlayer の `play(atTime:)` で遅らせて鳴らす予定は、鳴る前に `stop()` すれば取り消せる（2026-11-26、macOS で確かめた）
- Freesound の音は、元のファイルを取るにはログイン（API なら OAuth）が要るが、試聴用の MP3（`https://cdn.freesound.org/previews/<ID の上 3 桁>/<ID>_<作者の ID>-hq.mp3`、128kbps）はログインなしで取れる。URL は音のページに書いてある。検索は `https://freesound.org/search/?q=<語>&f=license:"Creative Commons 0"` で CC0 に絞れるが、ライセンスは音ごとのページ（`creativecommons.org/publicdomain/zero/1.0/` へのリンク）でも確かめる（2026-11-26）

## 動画

- AVAssetWriter に絵と音の 2 つの入力を足して `expectsMediaDataInRealTime = false` で書くとき、音を「絵の時刻 + 0.5 秒」までしか書かないと、絵の入力が受け取れないまま止まった（書き手は自分の区切りで交互に並べるので、もっと先の音を待つ）。絵を受け取れないときは、音を 1 回分ずつ先に書いてから見直す（`ReplayVideoEncoder`）（2026-11-26）
- 1080×1920 の SwiftUI を ImageRenderer で 1 コマずつ描くと、Mac では 1 コマ 5ms ほどで、10 秒の動画が 1〜2 秒で書き出せた。描いた絵を手放せば、描くだけでは使用量はほとんど増えない（全部のコマを描いて +10MB）。書き出しの間に増えるのは符号化の係の中の分で、Mac（ハードウェアで符号化）は BGRA のまま渡すと +130MB、vImage で YUV（4:2:0）に詰め直し、`CVPixelBufferPoolCreatePixelBufferWithAuxAttributes` に `kCVPixelBufferPoolAllocationThresholdKey` を渡してプールから取れる数を抑えると +60MB ほどになった。iOS Simulator はソフトウェアで符号化するので、係が 40 コマほどを中に持ち、プールを抑えても +410MB ほどで頭打ちになる（書き終えると戻る）。Simulator の使用量で実機を見積もらない。CI（GitHub Actions）の Mac の仮想マシンでは、描くだけで +465MB（描くときの絵の置き場。2 回目は増えない）になるので、使用量のテストは絶対の値ではなく、2 回目に増えないことで確かめる。`render(rasterizationScale:)` で自分の CGContext に描く（CPU で描く）方法は、3 倍遅く、使用量もあまり変わらなかった（2026-11-26）
- SwiftUI の `VideoPlayer`（`import AVKit`）だけを使うと、アプリに AVKit.framework が結び付けられず（`otool -L` に `_AVKit_SwiftUI` だけが出る）、Mac で見本を出したところで `failed to demangle superclass of VideoPlayerView from mangled name 'So12AVPlayerViewC'` で落ちた。`AVPlayerView`（Mac）・`AVPlayerViewController`（iOS）を Representable で直接使うと、AVKit が結び付けられて落ちない（2026-11-26）

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
- Mac で撮影モードを `open -n <app> --args` で起動するときは、`-screenshot-demo YES -screenshot-scene <場面>` のように `-screenshot-demo` にも値を付ける。値を付けないと、ウィンドウが開かなかった。設定の値も `-tapToDonate YES` のように起動引数（UserDefaults の引数のドメイン）で渡せる（2026-11-26）
- Mac のアプリを Bash から起動して `screencapture -l` で撮るとき、前の起動のウィンドウの状態が残っていると、テンプレートの WindowGroup の版はウィンドウを開かないことがある。`-ApplePersistenceIgnoreState YES` を付けると開いた。ただし `Window` シーンの版では、この引数を付けるとウィンドウが開かなかったので付けない（2026-11-12）

