#!/bin/sh
# Роль 2/3: накатка патчей из patches/ в decode/ (патчи перечислены в patches/README)
K="$(dirname "$0")/.."
cd "$K"
for p in patches/f*; do
  [ -f "$p" ] || continue
  echo "apply: $p"
  case "$p" in
    *.smali) cp "$p" "decode/$p" ;;                       # новые файлы
    *.patch) patch -d decode/ -p1 < "$p" ;;               # unified diffs
  esac
done
echo "патчи применены"
