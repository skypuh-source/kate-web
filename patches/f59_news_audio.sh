#!/bin/sh
# патч f59 (2026-11-19): треки в основной ленте новостей.
#
# Диагностика (f59, 2026-11-19) показала:
#   * раздел «Источники новостей» → «Аудио» (filter=audio,ads_post) отдаёт
#     items с type=audio, данные трека лежат в item.audio.items[];
#   * NewsItem.parse, serializeAttachments и NewsCursorAdapter уже умеют
#     разбирать, хранить и рисовать такие элементы — аудио-вкладка работает;
#   * основная лента запрашивает filters=post,photo,photo_tag[,friend]
#     + ads_post, то есть БЕЗ audio, поэтому VK не возвращает audio-новости
#     в обычные вкладки.
#
# Фикс: добавляем ",audio" к базовому фильтру ленты. Проверено на устройстве:
# вкладка «Друзья» (source_ids=friends) теперь отдаёт type=audio вместе с
# постами (4 трека + 12 постов), и они рисуются.
#
# Ограничение VK (проверено): вкладка «Все» (source_ids не задан) и
# «Сообщества» (source_ids=groups,pages) audio-элементы не возвращает даже
# с filters=...,audio. Явный source_ids=friends,following,groups,pages тоже
# не помогает. То есть треки доступны в «Друзьях» и во вкладке «Аудио»,
# но не в «Все» — это поведение выдачи VK, а не разбора.
#
# Дополнительно: в DataHelper.serializeAttachments поля audio.artist/title/url
# пишутся через writeUTF без проверки на null. Audio.parse оставляет url = null,
# если VK не прислал ссылку (нераспознанный/недоступный трек). writeUTF(null)
# бросает NPE, и теряется ВЕСЬ блоб вложений поста, а не только аудио.
# Добавляем подстановку пустой строки.
K="$(dirname "$0")/../"
cd "$K" || exit 1

F=decode/smali/com/perm/kate/NewsFragment.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

anchor = '''    :cond_4
    const/4 v0, -0x6
'''

inject = '''    :cond_4
    # f59_news_audio: audio в основной ленте
    invoke-virtual {v1}, Ljava/lang/String;->isEmpty()Z

    move-result v0

    if-eqz v0, :cond_f59_empty

    const-string v0, "audio"

    goto :goto_f59_base

    :cond_f59_empty
    const-string v0, ",audio"

    :goto_f59_base
    invoke-virtual {v1, v0}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v1

    const/4 v0, -0x6
'''

if "f59_news_audio" in s:
    print("f59 NewsFragment: уже применён")
else:
    assert s.count(anchor) == 1, "f59: якорь initFilterParams не найден/не уникален"
    s = s.replace(anchor, inject, 1)
    open(f, "w").write(s)
    print("f59 NewsFragment: ,audio добавлен к фильтру ленты")
EOF

F=decode/smali/com/perm/kate/db/DataHelper.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

# 1. В начале audio-ветки сбрасываем v4 в "" (v4 — общий scratch для "").
old_head = '''    const-string v5, "audio"

    invoke-virtual {v3, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v3

    if-eqz v3, :cond_15

    .line 5006'''

new_head = '''    const-string v5, "audio"

    invoke-virtual {v3, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v3

    if-eqz v3, :cond_15

    # f59_audio_null: v4 = "" для null-полей
    const-string v4, ""

    .line 5006'''

if "f59_audio_null" in s:
    print("f59 DataHelper: сброс v4 уже есть")
else:
    assert s.count(old_head) == 1, "f59: якорь audio-ветки не найден/не уникален"
    s = s.replace(old_head, new_head, 1)

# 2. artist/title/url: null -> "".
pairs = [
    ("artist", "Ljava/lang/String;"),
    ("title", "Ljava/lang/String;"),
    ("url", "Ljava/lang/String;"),
]
for field, sig in pairs:
    old = f'''    iget-object v3, v2, Lcom/perm/kate/api/Attachment;->audio:Lcom/perm/kate/api/Audio;

    iget-object v3, v3, Lcom/perm/kate/api/Audio;->{field}:{sig}

    invoke-virtual {{v1, v3}}, Ljava/io/DataOutputStream;->writeUTF(Ljava/lang/String;)V'''
    new = f'''    iget-object v3, v2, Lcom/perm/kate/api/Attachment;->audio:Lcom/perm/kate/api/Audio;

    iget-object v3, v3, Lcom/perm/kate/api/Audio;->{field}:{sig}

    if-nez v3, :cond_f59_{field}

    move-object v3, v4

    :cond_f59_{field}
    invoke-virtual {{v1, v3}}, Ljava/io/DataOutputStream;->writeUTF(Ljava/lang/String;)V'''
    if f":cond_f59_{field}" in s:
        print(f"f59 DataHelper: {field} уже защищён")
        continue
    assert s.count(old) == 1, f"f59: якорь {field} не найден/не уникален"
    s = s.replace(old, new, 1)
    print(f"f59 DataHelper: {field} null -> \"\"")

open(f, "w").write(s)
EOF
