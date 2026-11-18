#!/bin/sh
# патч f58a (2026-11-18): кэш картинок по умолчанию 150 МБ вместо 20 МБ.
#
# Проблема: в preferences.xml у image_cache_size_2 defaultValue="1" (20 МБ),
# а ImageLoader.getCacheSizeFromPreferences тем же значением "1" подставляет
# дефолт и одновременно сравнивает его с выбранным 20 МБ. При лимите 20 МБ
# кэш упирается в ~499 файлов (getMaxFiles = МБ*1024/41), и аватарки диалогов
# вытесняются.
#
# Фикс:
#   * preferences.xml: defaultValue 1 -> 2 (150 МБ) для чистых установок;
#   * ImageLoader: дефолт getString -> "2", а ветка 20 МБ продолжает сравнивать
#     с "1" (пользовательский выбор 20 МБ не ломается).
#
# Существующие установки со старым сохранённым "1" остаются на 20 МБ: это
# осознанный выбор в настройках, а на текущем устройстве уже стоит "2".
K="$(dirname "$0")/../"
cd "$K" || exit 1
python3 - <<'EOF'
import re

# 1. preferences.xml
p = "decode/res/xml/preferences.xml"
s = open(p).read()
old = 'android:key="image_cache_size_2" android:defaultValue="1"'
new = 'android:key="image_cache_size_2" android:defaultValue="2"'
if old in s:
    s = s.replace(old, new, 1)
    open(p, "w").write(s)
    print("f58a preferences.xml: defaultValue 1 -> 2")
elif new in s:
    print("f58a preferences.xml: уже применён")
else:
    raise SystemExit("f58a: якорь defaultValue не найден")

# 2. ImageLoader: дефолт "1" -> "2"
p = "decode/smali/com/perm/kate/ImageLoader.smali"
s = open(p).read()

old_default = '''    const-string v1, "image_cache_size_2"

    const-string v2, "1"

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getString(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;'''

new_default = '''    const-string v1, "image_cache_size_2"

    const-string v2, "2"

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getString(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;'''

if old_default in s:
    assert s.count(old_default) == 1, "f58a: дефолт не уникален"
    s = s.replace(old_default, new_default, 1)
    print("f58a ImageLoader: дефолт 20 МБ -> 150 МБ")
elif new_default in s:
    print("f58a ImageLoader: дефолт уже 150 МБ")
else:
    raise SystemExit("f58a: якорь дефолта не найден")

# 3. Ветка 20 МБ должна сравнивать с "1", а не с новым дефолтом v2.
old_cmp = '''    invoke-virtual {v0, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :cond_1

    const/16 v0, 0x14'''
new_cmp = '''    const-string v1, "1"

    invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :cond_1

    const/16 v0, 0x14'''

if old_cmp in s:
    assert s.count(old_cmp) == 1, "f58a: ветка 20 МБ не уникальна"
    s = s.replace(old_cmp, new_cmp, 1)
    open(p, "w").write(s)
    print("f58a ImageLoader: ветка 20 МБ сохранена")
elif new_cmp in s:
    print("f58a ImageLoader: ветка 20 МБ уже исправлена")
else:
    raise SystemExit("f58a: якорь ветки 20 МБ не найден")
EOF
