#!/bin/bash
#
# Mac と iPad の横長の画面に使う紙の背景（paper-wide.jpg）を、元画像（引き継ぎ資料の assets/source/paper.jpg）から作る。
# 引き継ぎの paper-bg.jpg は iPhone の縦長（780 × 1688）に切り抜いてあり、横長の画面に広げると粗くなるため。
#
#   Tools/artwork/make_paper_wide.sh ~/Desktop/ios/UncleRAM-handoff/assets/source/paper.jpg UncleRAM/Assets.xcassets/PaperWide.imageset/paper-wide.jpg
#
# 元画像（2000 × 1813）の中央を、Mac のデザイン（1200 × 760）と同じ比率の 2000 × 1266 に切り抜く。
set -euo pipefail
source_path="$1"
output_path="$2"
sips -c 1266 2000 "$source_path" --out "$output_path" >/dev/null
sips -s format jpeg -s formatOptions 72 "$output_path" --out "$output_path" >/dev/null
sips -g pixelWidth -g pixelHeight "$output_path"
