#!/usr/bin/env python3
"""アプリに入れる効果音を作る（docs/SPEC.md「音と振動」、出典は docs/HANDOFF.md「素材の出典とライセンス」）。

Freesound の CC0 の音を、決まったファイル（ハッシュを固定）で取ってきて、`Tools/sounds/edit.swift` で切り出し・フェード・
音量の調整をし、afconvert で AAC（.m4a）にして `UncleRAM/Sounds/` に置く。macOS の標準の道具だけで動く（ffmpeg・sox は使わない）。

    python3 Tools/sounds/make_sounds.py

- 元の音はリポジトリに入れない。取ってきたものは `~/Library/Caches/uncleram-sounds/` に置き、次からはそれを使う
- 取ってくるのは Freesound の試聴用のファイル（ログインせずに取れる MP3）。音そのものは元のファイルと同じで、ライセンスも同じ CC0
- 使うのは CC0 かパブリックドメインと明記された音だけ。音を足したり替えたりしたら、`SOURCES` と、
  設定の「ライセンス」（UncleRAM/UI/SettingsScreen.swift の `LicensesPage`）と、docs/HANDOFF.md の表をそろえる
- 切り出す位置や音量を変えるときは `edit.swift` の数値を変える。ハッシュは初回に表示される値を確かめてから書く
- 作り直すと、.m4a の中の作った日時（数バイト）だけが変わる。音そのものは同じなので、音を変えないときは作り直したものをコミットしない
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EDITOR = Path(__file__).with_name("edit.swift")
OUTPUT = ROOT / "UncleRAM" / "Sounds"
CACHE = Path.home() / "Library" / "Caches" / "uncleram-sounds"

# AAC のビットレート（モノラル）。効果音だけで 1MB 前後を目安にする（docs/SPEC.md の上限は音の合計 20MB）
BITRATE = 64_000

# (edit.swift に渡す名前, 試聴用のファイルの URL, SHA-256, 音のページ)。どれも Creative Commons 0（2026-11-26 に取得）
SOURCES = [
    (
        "propeller",  # ilm0player「Airship propeller engine」
        "https://cdn.freesound.org/previews/578/578181_8061009-hq.mp3",
        "b05dc26d1594c1029989334710991e93a7a6c266e90f97c7643f7d7cb6225494",
        "https://freesound.org/people/ilm0player/sounds/578181/",
    ),
    (
        "stamp",  # kermite607「Stamp」
        "https://cdn.freesound.org/previews/362/362624_3165091-hq.mp3",
        "daaad886f71a57dca4b097550c1ecb4cc99d4fe3d7dd383841091c000cd6ab26",
        "https://freesound.org/people/kermite607/sounds/362624/",
    ),
    (
        "bell",  # ramsamba「Typewriter Bell.wav」
        "https://cdn.freesound.org/previews/318/318687_1147663-hq.mp3",
        "8f669d70aa26c82cf6de344c8d4ebe8f8eff39cc62fffaa92c9e98222e2e174c",
        "https://freesound.org/people/ramsamba/sounds/318687/",
    ),
    (
        "whistle",  # Bidone「Steam Whistle.mp3」
        "https://cdn.freesound.org/previews/71/71778_706955-hq.mp3",
        "42c528eda2c2038fa3dce9ae32c430acce64dec23bc58886307a333c597d8d8c",
        "https://freesound.org/people/Bidone/sounds/71778/",
    ),
    (
        "typewriter",  # escritor1「Typewriter Typing.wav」
        "https://cdn.freesound.org/previews/455/455044_3232276-hq.mp3",
        "6294b96ccee185a403e89f4830f383514a7bb145e01bae3db9a12c39359285bd",
        "https://freesound.org/people/escritor1/sounds/455044/",
    ),
]

# edit.swift が書き出す音（アプリの SoundEffect の名前と同じ）
OUTPUTS = ["propeller", "delivered", "whistle", "receipt"]


def fetch(url: str, sha256: str) -> Path:
    cached = CACHE / sha256 / Path(url).name
    if cached.exists():
        data = cached.read_bytes()
    else:
        print(f"取得: {url}")
        request = urllib.request.Request(url, headers={"User-Agent": "uncleram-make-sounds"})
        with urllib.request.urlopen(request, timeout=120) as response:
            data = response.read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != sha256:
        sys.exit(f"{url} のハッシュが違います: {digest}（期待した値 {sha256}）")
    cached.parent.mkdir(parents=True, exist_ok=True)
    cached.write_bytes(data)
    return cached


def main() -> None:
    sources = [(name, fetch(url, sha256)) for name, url, sha256, _ in SOURCES]
    with tempfile.TemporaryDirectory(prefix="uncleram-sounds-") as work:
        editor = Path(work) / "edit"
        subprocess.run(["swiftc", "-O", str(EDITOR), "-o", str(editor)], check=True)
        edited = Path(work) / "edited"
        edited.mkdir()
        subprocess.run([str(editor), str(edited), *(f"{name}={path}" for name, path in sources)], check=True)
        if OUTPUT.exists():
            shutil.rmtree(OUTPUT)
        OUTPUT.mkdir(parents=True)
        total = 0
        for name in OUTPUTS:
            output = OUTPUT / f"{name}.m4a"
            subprocess.run(
                ["afconvert", "-f", "m4af", "-d", "aac", "-b", str(BITRATE), str(edited / f"{name}.caf"), str(output)],
                check=True,
            )
            size = output.stat().st_size
            total += size
            print(f"{output.relative_to(ROOT)}: {size / 1024:.0f} KB")
        print(f"合計: {total / 1024:.0f} KB")


if __name__ == "__main__":
    main()
