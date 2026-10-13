#!/bin/sh
# Роль 2/3: накатка патчей из patches/ в decode/
# f*.smali — копируются на место; f*.sh — выполняются (точечные правки)
K="$(dirname "$0")/.."
cd "$K"
for p in patches/f*; do
  base=$(basename "$p")
  if [ -d "$p" ]; then
    for sf in "$p"/*.smali; do
      cp "$sf" "decode/smali/com/perm/kate/api/"
    done
    echo "apply: $base/*.smali -> decode/smali/com/perm/kate/api/"
    continue
  fi
  [ -f "$p" ] || continue
  case "$base" in
    *.smali)
      dst="decode/smali/com/perm/kate/api/WebChannel.smali"
      cp "$p" "$dst"
      echo "apply: $base -> $dst" ;;
    *.sh)
      sh "$p" ;;
  esac
done
echo "патчи применены"