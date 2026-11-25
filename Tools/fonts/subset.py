#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["fonttools==4.60.1"]
# ///
"""アプリに入れる書体を用意する（docs/HANDOFF.md「デザインの実装メモ」の書体）。

google/fonts の決まったコミットから書体とライセンス（OFL.txt）を取り、`UncleRAM/Fonts/` に置く。
日本語の書体は 1 つの太さで約 15MB あるので、アプリの文言に出てくる文字だけに絞る。

    uv run Tools/fonts/subset.py           # 書体を作り直す（fontTools を使う）
    python3 Tools/fonts/subset.py --check  # 文言の文字が、絞った文字にすべて入っているかだけを見る（CI で流す）

- 文言を変えて、新しい漢字などが増えたら回し直す。回し忘れは CI の `--check` が見つける
- 絞る文字は、`UncleRAM/` の Swift の文字列リテラル（コメントは除く）と、仮名・記号の基本の文字（`BASE_CHARACTERS`）。
  コードに書かない文字を足すときは `Tools/fonts/extra_characters.txt` に書く
- 絞った文字の一覧は `Tools/fonts/characters.txt` に書き出す（PR で増えた文字が分かるように）
- 書体を足すときは `FONTS` に足し、ハッシュは初回に表示される値を確かめてから書く
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "UncleRAM"
OUTPUT = ROOT / "UncleRAM" / "Fonts"
CHARACTERS = Path(__file__).with_name("characters.txt")
EXTRA_CHARACTERS = Path(__file__).with_name("extra_characters.txt")
CACHE = Path.home() / "Library" / "Caches" / "uncleram-fonts"

# 2026-11-26 の google/fonts の main。書体を更新するときは、こことハッシュを一緒に変える
GOOGLE_FONTS_COMMIT = "6ebe737e44fd64ee736bbc6feed6136a6dbfd222"

# (google/fonts の ofl/ からのパス, SHA-256, 文字を絞るか)
FONTS = [
    ("archivoblack/ArchivoBlack-Regular.ttf", "dd9a89a019b4849f66ab75455fe7bdf931311042cbb0f0f97acc061539703180", False),
    ("courierprime/CourierPrime-Bold.ttf", "ff1f38786c849d1c41fa8e447960abdb2bd75fdfb0cfcdeb524fad65a5af3638", False),
    ("shipporiminchob1/ShipporiMinchoB1-Medium.ttf", "0712348124729e30507a9ed9d7c8939125f13605954596acfe0ec4a6341e3b9d", True),
    ("shipporiminchob1/ShipporiMinchoB1-Bold.ttf", "d20f3981afb8bceda5fdf8f0fb29ba51eb21518644612ccd8a183e5bd433e25a", True),
    ("shipporiminchob1/ShipporiMinchoB1-ExtraBold.ttf", "bee99a242f32128e8d6a4acff2b3f1742cd42ea90748758e6e10456871887e76", True),
    ("delagothicone/DelaGothicOne-Regular.ttf", "4ff87a0965f1b0505e5a2c58424bc6ad3cff27e56a82f21c2fc9d6b0e3857ee2", True),
]

# (google/fonts の ofl/ からのパス, SHA-256, アプリに入れる名前)
LICENSES = [
    ("archivoblack/OFL.txt", "3173acd82f8c6159b5b1037b539fcbd4edff68e65c2ea8b9412b5a5ca97b08ff", "OFL-ArchivoBlack.txt"),
    ("courierprime/OFL.txt", "9a755af092b494944c99f471be6fddd19b006a448fefdc4717e4ee0aa09a97b0", "OFL-CourierPrime.txt"),
    ("shipporiminchob1/OFL.txt", "41fba056279be5f45ff9a99e44b7b53897b42732f5806d8e666e0ab49ac6bd38", "OFL-ShipporiMinchoB1.txt"),
    ("delagothicone/OFL.txt", "c0014792d4f4abc0508c295b277f2b17ae44465c8dc88d12af9cea48279b5fda", "OFL-DelaGothicOne.txt"),
]


def _range(first: int, last: int) -> str:
    return "".join(chr(code) for code in range(first, last + 1))


# 文言を少し変えただけで回し直さずに済むよう、仮名と記号は全部入れておく（漢字だけを文言から拾う）
BASE_CHARACTERS = (
    _range(0x20, 0x7E)  # ASCII
    + _range(0x3000, 0x303F)  # 和文の約物（、。「」〜 など）
    + _range(0x3041, 0x3096) + _range(0x309B, 0x309F)  # 平仮名
    + _range(0x30A0, 0x30FF)  # 片仮名
    + _range(0xFF01, 0xFF5E)  # 全角の英数字と記号
    + "×÷±°%‰…‥—–‐‘’“”•※¥¢£€→←↑↓⇒≤≥≠〜～▲▼△▽◆◇■□●○◎★☆♪"
)


def swift_string_literals(source: str) -> list[str]:
    """Swift のソースから文字列リテラルの中身を取り出す（コメントは飛ばす）"""
    literals: list[str] = []
    index, end = 0, len(source)
    while index < end:
        if source.startswith("//", index):
            newline = source.find("\n", index)
            index = end if newline < 0 else newline
        elif source.startswith("/*", index):
            depth, index = 1, index + 2
            while index < end and depth:
                if source.startswith("/*", index):
                    depth, index = depth + 1, index + 2
                elif source.startswith("*/", index):
                    depth, index = depth - 1, index + 2
                else:
                    index += 1
        elif source.startswith('"""', index):
            close = source.find('"""', index + 3)
            close = end if close < 0 else close
            literals.append(source[index + 3 : close])
            index = close + 3
        elif source[index] == '"':
            cursor = index + 1
            while cursor < end and source[cursor] not in '"\n':
                cursor += 2 if source[cursor] == "\\" else 1
            literals.append(source[index + 1 : cursor])
            index = cursor + 1
        else:
            index += 1
    return literals


def collect_characters() -> str:
    characters = set(BASE_CHARACTERS)
    for path in sorted(SOURCES.rglob("*.swift")):
        for literal in swift_string_literals(path.read_text(encoding="utf-8")):
            characters.update(literal)
    if EXTRA_CHARACTERS.exists():
        characters.update(EXTRA_CHARACTERS.read_text(encoding="utf-8"))
    characters -= set("\n\r\t")
    return "".join(sorted(characters))


def fetch(path: str, sha256: str) -> bytes:
    cached = CACHE / GOOGLE_FONTS_COMMIT / path
    if cached.exists():
        data = cached.read_bytes()
    else:
        url = f"https://raw.githubusercontent.com/google/fonts/{GOOGLE_FONTS_COMMIT}/ofl/{path}"
        print(f"取得: {url}")
        with urllib.request.urlopen(url, timeout=120) as response:
            data = response.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != sha256:
        sys.exit(f"{path} のハッシュが違います: {digest}（期待した値 {sha256}）")
    cached.parent.mkdir(parents=True, exist_ok=True)
    cached.write_bytes(data)
    return data


def subset_font(data: bytes, characters: str, output: Path) -> None:
    from fontTools import subset  # --check のときは要らないので、ここで読む

    source = output.with_suffix(".source.ttf")
    source.write_bytes(data)
    options = subset.Options()
    options.layout_features = ["*"]  # 約物の詰め（palt など）とカーニングを残す
    options.name_IDs = ["*"]  # 著作権表示とライセンスの名前を残す
    options.name_languages = ["*"]
    options.notdef_outline = True
    options.hinting = False  # iOS と macOS はヒントを使わない
    try:
        font = subset.load_font(str(source), options)
        subsetter = subset.Subsetter(options)
        subsetter.populate(text=characters)
        subsetter.subset(font)
        subset.save_font(font, str(output), options)
    finally:
        source.unlink()


def check() -> None:
    """今の文言の文字が、前に絞った文字（characters.txt）にすべて入っているか"""
    recorded = set(CHARACTERS.read_text(encoding="utf-8")) if CHARACTERS.exists() else set()
    missing = "".join(sorted(set(collect_characters()) - recorded))
    if missing:
        sys.exit(f"書体に入っていない文字があります: {missing}\n`uv run Tools/fonts/subset.py` で書体を作り直してください")
    print("文言の文字は、すべて書体に入っています")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="書体は作らず、文言の文字が入っているかだけを見る")
    if parser.parse_args().check:
        check()
        return
    characters = collect_characters()
    CHARACTERS.write_text(characters + "\n", encoding="utf-8")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for path, sha256, should_subset in FONTS:
        data = fetch(path, sha256)
        output = OUTPUT / Path(path).name
        if should_subset:
            subset_font(data, characters, output)
        else:
            output.write_bytes(data)
        print(f"{output.relative_to(ROOT)}: {output.stat().st_size / 1024:.0f} KB")
    for path, sha256, name in LICENSES:
        (OUTPUT / name).write_bytes(fetch(path, sha256))
    print(f"文字: {len(characters)} 字（{CHARACTERS.relative_to(ROOT)}）")


if __name__ == "__main__":
    main()
