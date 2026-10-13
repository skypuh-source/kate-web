#!/bin/sh
# Роль 3: сборка + подпись → dist/kate_web-<дата>.apk
K="$(dirname "$0")/.."
cd "$K"
TS=$(date +%Y-%m-%d)
OUT="dist/kate_web-$TS.apk"
java -jar tools/apktool_2.12.1.jar b decode -o dist/_unsigned.apk || exit 1
jarsigner -keystore keys/debug.keystore -storepass android \
  -signedjar "$OUT" dist/_unsigned.apk androiddebugkey || exit 1
jarsigner -verify "$OUT" || exit 1
MD5=$(md5 -q "$OUT")
echo "$TS $OUT $MD5" >> HISTORY.md
echo "OK: $OUT (md5 $MD5)"
