#!/bin/sh
# Роль 3: декомпиляция оригинала в рабочее дерево
K="$(dirname "$0")/.."
cd "$K"
rm -rf decode
java -jar tools/apktool_2.12.1.jar d orig/Kate_133_11.apk -f -o decode
echo "decode готов: $K/decode"
