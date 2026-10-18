#!/usr/bin/env bash
# 클라우드 세션에서 로블록스 개발 도구와 공식 문서를 한 번에 받는 스크립트.
# 사용: tools/setup-roblox-tools.sh [설치_폴더]   (기본: $SCRATCH 또는 /tmp/roblox-tools)
set -euo pipefail
DEST="${1:-${SCRATCH:-/tmp/roblox-tools}}"
mkdir -p "$DEST/bin"
cd "$DEST"

dl() { # name url
  echo ">> $1"
  curl -sSL -o "$1.zip" "$2"
  unzip -oq "$1.zip" -d bin
  rm -f "$1.zip"
}
dl rojo   https://github.com/rojo-rbx/rojo/releases/download/v7.5.1/rojo-7.5.1-linux-x86_64.zip
dl lune   https://github.com/lune-org/lune/releases/download/v0.10.4/lune-0.10.4-linux-x86_64.zip
dl selene https://github.com/Kampfkarren/selene/releases/download/0.29.0/selene-0.29.0-linux.zip
dl stylua https://github.com/JohnnyMorganz/StyLua/releases/download/v2.3.1/stylua-linux-x86_64.zip
chmod +x bin/*

if [ ! -d roblox-docs/creator-docs ]; then
  echo ">> Roblox creator-docs (sparse: content/en-us)"
  mkdir -p roblox-docs && cd roblox-docs
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/Roblox/creator-docs.git
  cd creator-docs && git sparse-checkout set content/en-us && cd "$DEST"
fi

echo
echo "done. add to PATH:  export PATH=\"$DEST/bin:\$PATH\""
echo "docs:               $DEST/roblox-docs/creator-docs/content/en-us"
"$DEST/bin/rojo" --version; "$DEST/bin/lune" --version; "$DEST/bin/selene" --version; "$DEST/bin/stylua" --version
