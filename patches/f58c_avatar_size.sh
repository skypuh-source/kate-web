#!/bin/sh
# патч f58c (2026-11-18): аватарки диалогов запрашиваются в 160 px вместо 80 px.
#
# dialog_item.xml рисует img_message_photo в 53 dip (≈159 px на текущей
# плотности), а DialogsAdapter просит у ImageLoader 0x50 = 80 px. Картинка
# растягивается, выглядит мылом и перезагружается при смене размера.
#
# Фикс: все размеры аватарок в DialogsAdapter (пользователь, группа, я, чат)
# 0x50 -> 0xA0 (160 px). Стубы и логика не меняются.
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/DialogsAdapter.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

pairs = [("const/16 v21, 0x50", "const/16 v21, 0xA0"),
         ("const/16 v20, 0x50", "const/16 v20, 0xA0")]

changed = 0
for old, new in pairs:
    n = s.count(old)
    if n:
        s = s.replace(old, new)
        changed += n
        print(f"f58c DialogsAdapter: {old} -> {new} ({n} шт.)")
    elif new in s:
        print(f"f58c DialogsAdapter: {new} уже стоит")

if changed == 0:
    if "0xA0" not in s:
        raise SystemExit("f58c: якоря 0x50 не найдены")
else:
    open(f, "w").write(s)
    print(f"f58c DialogsAdapter: всего заменено {changed}")
EOF
