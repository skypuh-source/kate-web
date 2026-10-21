#!/bin/sh
set -eu
K="$(dirname "$0")/.."
cd "$K"
mkdir -p dist
TS=$(date +%Y-%m-%d)
OUT="dist/kate_web-$TS.apk"
java -jar tools/apktool_2.12.1.jar b decode -o dist/_unsigned.apk
jarsigner -keystore keys/debug.keystore -storepass android \
  -signedjar "$OUT" dist/_unsigned.apk androiddebugkey
jarsigner -verify "$OUT"
if command -v md5 >/dev/null 2>&1; then
  MD5=$(md5 -q "$OUT")
else
  MD5=$(md5sum "$OUT" | awk '{print $1}')
fi
echo "OK: $OUT (md5 $MD5)"
