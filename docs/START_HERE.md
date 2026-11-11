# Uncle RAM 本実装の依頼書

> このファイルは引き継ぎ資料（UncleRAM-handoff、2026-11-12 時点の書き出し）の写しです。リポジトリでの置き場所の違い（`tools/` → `Tools/` など）は [CLAUDE.md](../CLAUDE.md) の「資料」を見てください。

このフォルダ（`UncleRAM-handoff`）は、別の PC の Claude Code に Uncle RAM の本実装を頼むための一式です。**このフォルダだけで完結しています。** 中の URL は作った人のアカウントでしか開けないことがあるので、開けなくても作業に困らないようにしてあります。

仕様は 2026-11-12 にユーザーが確認済みです。

## 置き場所の決まり

開発する PC では、iOS のリポジトリをすべて `~/Desktop/ios/` の中に clone しています。Uncle RAM もそれに合わせます。

```text
~/Desktop/ios/
├── UncleRAM-handoff/     ← この一式（zip を展開したもの。参考資料として残す）
├── uncleram-ios/         ← 新しく作るリポジトリ（GitHub: shilokuma-inc/uncleram-ios）
└── （ほかの iOS リポジトリ）
```

## 人がすること（別の PC で）

1. `UncleRAM-handoff.zip` を `~/Desktop/ios/` の中で展開する。`~/Desktop/ios/UncleRAM-handoff/START_HERE.md` ができる。
2. `~/Desktop/ios/` で Claude Code のセッションを始める（リポジトリはまだないので、1 つ上の `ios` で始める）。
3. 下の「依頼文」を、最初のメッセージとして貼る。

## 依頼文（コピーして使う）

```text
Uncle RAM（iPhone / iPad / Mac のゲーム）の本実装をお願いします。
仕様・デザイン・素材は ~/Desktop/ios/UncleRAM-handoff/ にまとまっています。
まず UncleRAM-handoff/START_HERE.md を読み、次に UncleRAM-handoff/HANDOFF.md を読んで、その段取りに沿って進めてください。

- 仕様は確認済みです。仕様の正は UncleRAM-handoff/SPEC.md です。食い違うときは「ゲーム性の見直し」「説明なしで分かる UI」の節を最優先にし、次に「実装の詳細」の節を優先します。
- 画面は UncleRAM-handoff/design/png/ の画像に合わせてください（同じ名前の design/*.html はブラウザで開ける元データです）。
- 最初の作業は「準備」です。template-app-ios（https://github.com/shilokuma-inc/template-app-ios）から GitHub に shilokuma-inc/uncleram-ios を作り、~/Desktop/ios/uncleram-ios に clone してください。リポジトリ名は uncleram-ios で確定です。公開か非公開かだけ、作る前に私に確認してください。
- clone したら、セッションをそのリポジトリのフォルダへ移してから作業してください。
- 試作の合格条件（HANDOFF.md の「段取り」2）を満たすまでは、ほかの機能に手を広げないでください。
- 仕様で決まっていない点に当たったら、推測で埋めずに私に聞いてください。
```

## 読む順番

| 順番 | ファイル | 何が分かるか |
| --- | --- | --- |
| 1 | このファイル | 依頼の範囲、最初の一歩、守ること |
| 2 | [review/index.html](review/index.html) | 仕様の要点とデザイン 42 枚の一覧。ブラウザで開く。全体をつかむのに一番早い |
| 3 | [HANDOFF.md](HANDOFF.md) | 決定事項、数値の初期値、部品の分け方、マイルストーン、まだ確かめていないこと |
| 4 | [SPEC.md](SPEC.md) | 仕様書の全文。細かい挙動はここを引く |
| 5 | [design/png/](design/png/) | 画面デザイン 42 枚の画像（2 倍の解像度）。`design/*.html` はその元データ |
| 6 | [tools/sim.py](tools/sim.py) | 早期回収・ヒント・速さの数値の試算。数値を変えたら回し直す（`python3 tools/sim.py`） |

- [mock/](mock/) の Web モックは、ゲーム性を見直す前の古いルールで動いています。遊び心地の目安にとどめ、数値と流れは SPEC.md に従ってください。
- `design/*.html` と `review/index.html` は書体を Google Fonts から読みます。ネットにつながっていないと、代わりの書体で表示されます。画像（`design/png/`）はネットがなくても正しく見えます。

## 最初の一歩（準備）

1. template-app-ios から `uncleram-ios` リポジトリを作る（名前は確定。公開か非公開かだけ、作る前にユーザーに確認する）。`~/Desktop/ios/uncleram-ios` に clone し、セッションをそのフォルダへ移す。
   - 例: `gh repo create shilokuma-inc/uncleram-ios --template shilokuma-inc/template-app-ios --private --clone`（`~/Desktop/ios/` で実行する。公開にするなら `--public`）
   - リポジトリ名は `-ios` だが、iPhone・iPad・Mac を 1 つのリポジトリ・1 つのターゲットで作る
2. `scripts/rename.sh UncleRAM` を実行する。`Configs/Project.xcconfig` に Bundle ID `jp.shilokuma.UncleRAM` と iOS 18 を設定する。
3. 同じターゲットに macOS 15 を足す（Mac Catalyst ではない）。
4. `~/Desktop/ios/UncleRAM-handoff/` から、次のものをリポジトリにコピーする。
   - `START_HERE.md`・`HANDOFF.md`・`SPEC.md` → `docs/`
   - `design/png/` → `docs/design/`（画像だけでよい）
   - `assets/images/` と `assets/icon/` → アプリのアセットカタログ（必要な解像度へ書き出して取り込む）
   - `tools/` → `tools/`（網点の加工と sim.py）
   - `assets/source/`、`design/*.html`、`review/`、`mock/` はリポジトリに入れなくてよい（参考資料。`~/Desktop/ios/UncleRAM-handoff/` に残す）
5. CI に Mac 用の Archive・Export・Upload を足す。
6. 試作（速達便 1 ラウンド）に進む。

## 守ること

- **安全:** 確保のたびに安全ラインの 2 つの条件を必ず確かめる。`Allocator` 以外からメモリを確保しない。演出の前に全メモリを解放する。
- **審査:** 回収演出は OS の画面に似せない。「端末が速くなる」と読める表現を入れない。実在の人物・企業・ロゴを出さない。
- **名前:** アプリの中にも、ストアの説明にも、元ネタになった実在の人物の名前を出さない。
- **ランキング:** 課金・強化・保険が効くモード（定期便）はランキングに入れない。
- **見た目:** ライトモード固定。色と書体は HANDOFF.md の「デザインの実装メモ」のとおり。

## フォルダの中身

| パス | 中身 |
| --- | --- |
| `START_HERE.md` | このファイル |
| `HANDOFF.md` | 実装の要点 |
| `SPEC.md` | 仕様書の全文 |
| `review/` | 最終確認の資料（`index.html` をブラウザで開く） |
| `design/png/` | 画面デザイン 42 枚の画像 |
| `design/*.html`, `design/b/` | 画面デザインの元データと、その画像素材 |
| `mock/` | Web モック（古いルール） |
| `assets/images/` | アプリで使う加工済みの素材 |
| `assets/icon/` | アプリアイコン 1024px（通常・ダーク・色付き） |
| `assets/source/` | 加工前の元画像（出典は HANDOFF.md） |
| `tools/` | 網点の加工スクリプト（PIL）と数値の試算 sim.py |

## 参考: 元の資料の URL

作った人の claude.ai アカウントで作った非公開の資料です。同じアカウントなら Claude の Artifact ツールで読めますが、開けなくても問題ありません。このフォルダの中身は 2026-11-12 時点の書き出しで、内容は同じです。

| 資料 | URL | このフォルダでの写し |
| --- | --- | --- |
| 最終確認の資料 | https://claude.ai/artifact/Wb65MBEZh2oPhd1xcfEK48 | `review/` |
| 仕様書（Claude Docs） | https://claude.ai/artifact/JVJPxhVFsQbiPrUMGWga9v | `SPEC.md` |
| デザインキャンバス | https://claude.ai/artifact/FLBSKFQwgrNNTxseYVYcBM | `design/` |
