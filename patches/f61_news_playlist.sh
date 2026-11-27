#!/bin/sh
# патч f61 (2026-11-25): плейлисты во вложениях постов.
#
# Пост может нести не отдельный трек, а плейлист:
#   "attachments": [
#     {"type": "photo", ...},
#     {"type": "audio_playlist",
#      "audio_playlist": {"id": 85380604, "owner_id": 16178728,
#                         "access_key": "...", "title": "CHILL утро", "count": 21}}
#   ]
#
# Attachment.parseAttachments знает только "audio"/"photo"/"video"/"link"/…,
# поэтому audio_playlist молча терялся: в посте оставалась одна фотография,
# музыки не было видно (проверено на vk.com/wall-352896_329975).
# Неизвестные типы не попадают даже в список: ветка default уходит на
# `goto :goto_24` (продолжение цикла) и пропускает `ArrayList.add`.
#
# Фикс без новых моделей и без изменения формата БД: после разбора вложений
# проходим по исходному JSONArray ещё раз и для каждого audio_playlist
# добавляем обычный link-аттачмент:
#   title = title плейлиста
#   url   = https://vk.com/music/playlist/<owner_id>_<id>[_access_key]
# Дальше работает штатный путь:
#   * AttachmentsHelper рисует строку «Плейлист: <title>» (displayLink);
#   * клик по строке → Helper.openUrl → openVK_COMlink →
#     VkLinkParser.parseAudioPlaylist2 → AUDIO_PLAYLIST →
#     Helper.openAudioPlaylist → AudioActivity2 со списком треков.
#
# Дубликата не будет: parseAttachments сам audio_playlist не добавляет.
#
# Сериализация не меняется: link уже поддерживается в DataHelper
# (description/image_src/title/url, null-safe кроме url), поэтому после
# refresh плейлист сохраняется в БД как обычная ссылка.
K="$(dirname "$0")/../"
cd "$K" || exit 1

F=decode/smali/com/perm/kate/api/Attachment.smali

python3 - "$F" <<'EOF'
import sys

f = sys.argv[1]
s = open(f).read()

if "f61_playlist_convert" in s:
    print("f61: Attachment уже пропатчен")
    sys.exit(0)

# convertPlaylists(JSONArray, ArrayList<Attachment>)
# Регистры: .locals 16 -> v0..v15, p0=v16, p1=v17.
# Держим всё в v0..v15: часть инструкций (if-*, iput-object) в этой сборке
# smali допускает только 4-битные регистры.
#   v0 — длина массива   v1 — i        v2 — JSONObject (элемент/плейлист)
#   v3 — JSONArray       v4 — ArrayList
#   v5/v7 — temp string  v6 — новый Attachment
#   v8 — title           v9/v10 — owner_id
#   v11/v12 — id         v13 — access_key
#   v14 — StringBuilder/url   v15 — Link
helper = '''# f61_playlist_convert
# audio_playlist → link: плейлист открывается штатным AudioActivity2.
.method public static convertPlaylists(Lorg/json/JSONArray;Ljava/util/ArrayList;)V
    .locals 16

    if-eqz p0, :done

    if-eqz p1, :done

    move-object/from16 v3, p0

    move-object/from16 v4, p1

    invoke-virtual {v3}, Lorg/json/JSONArray;->length()I

    move-result v0

    const/4 v1, 0x0

    :loop
    if-ge v1, v0, :done

    :try_start_0
    invoke-virtual {v3, v1}, Lorg/json/JSONArray;->optJSONObject(I)Lorg/json/JSONObject;

    move-result-object v2

    if-eqz v2, :next

    const-string v5, "type"

    invoke-virtual {v2, v5}, Lorg/json/JSONObject;->optString(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v5

    const-string v7, "audio_playlist"

    invoke-virtual {v7, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v5

    if-eqz v5, :next

    const-string v5, "audio_playlist"

    invoke-virtual {v2, v5}, Lorg/json/JSONObject;->optJSONObject(Ljava/lang/String;)Lorg/json/JSONObject;

    move-result-object v2

    if-eqz v2, :next

    const-string v5, "title"

    invoke-virtual {v2, v5}, Lorg/json/JSONObject;->optString(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v8

    const-string v5, "owner_id"

    invoke-virtual {v2, v5}, Lorg/json/JSONObject;->optLong(Ljava/lang/String;)J

    move-result-wide v9

    const-string v5, "id"

    invoke-virtual {v2, v5}, Lorg/json/JSONObject;->optLong(Ljava/lang/String;)J

    move-result-wide v11

    const-string v5, "access_key"

    invoke-virtual {v2, v5}, Lorg/json/JSONObject;->optString(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v13

    new-instance v14, Ljava/lang/StringBuilder;

    invoke-direct {v14}, Ljava/lang/StringBuilder;-><init>()V

    const-string v7, "https://vk.com/music/playlist/"

    invoke-virtual {v14, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v14, v9, v10}, Ljava/lang/StringBuilder;->append(J)Ljava/lang/StringBuilder;

    const-string v7, "_"

    invoke-virtual {v14, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v14, v11, v12}, Ljava/lang/StringBuilder;->append(J)Ljava/lang/StringBuilder;

    if-eqz v13, :no_key

    invoke-virtual {v13}, Ljava/lang/String;->isEmpty()Z

    move-result v5

    if-eqz v5, :no_key

    const-string v7, "_"

    invoke-virtual {v14, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v14, v13}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    :no_key
    invoke-virtual {v14}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v14

    new-instance v15, Lcom/perm/kate/api/Link;

    invoke-direct {v15}, Lcom/perm/kate/api/Link;-><init>()V

    iput-object v8, v15, Lcom/perm/kate/api/Link;->title:Ljava/lang/String;

    iput-object v14, v15, Lcom/perm/kate/api/Link;->url:Ljava/lang/String;

    new-instance v6, Lcom/perm/kate/api/Attachment;

    invoke-direct {v6}, Lcom/perm/kate/api/Attachment;-><init>()V

    const-string v7, "link"

    iput-object v7, v6, Lcom/perm/kate/api/Attachment;->type:Ljava/lang/String;

    iput-object v15, v6, Lcom/perm/kate/api/Attachment;->link:Lcom/perm/kate/api/Link;

    invoke-virtual {v4, v6}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
    :try_end_0
    .catch Ljava/lang/Exception; {:try_start_0 .. :try_end_0} :catch_0

    :next
    add-int/lit8 v1, v1, 0x1

    goto :loop

    :catch_0
    goto :next

    :done
    return-void
.end method

'''

anchor_method = ".method public static parseAttachments(Lorg/json/JSONArray;JJLorg/json/JSONObject;)Ljava/util/ArrayList;"
assert s.count(anchor_method) == 1, "f61: parseAttachments не найден"
s = s.replace(anchor_method, helper + anchor_method, 1)

# В tail-е parseAttachments (перед добавлением geo) v2 — готовый ArrayList.
# v3 в этой точке мёртв, его и используем для JSONArray (p0 = v28,
# обычный invoke с v28 невозможен).
anchor_tail = """    :goto_25
    if-eqz p5, :cond_1c
"""
inject_tail = """    :goto_25
    move-object/from16 v3, p0

    invoke-static {v3, v2}, Lcom/perm/kate/api/Attachment;->convertPlaylists(Lorg/json/JSONArray;Ljava/util/ArrayList;)V

    if-eqz p5, :cond_1c
"""
assert s.count(anchor_tail) == 1, "f61: хвост parseAttachments не найден"
s = s.replace(anchor_tail, inject_tail, 1)

open(f, "w").write(s)
print("f61 Attachment: audio_playlist → link")
EOF

F=decode/smali/com/perm/kate/AttachmentsHelper.smali

python3 - "$F" <<'EOF'
import sys

f = sys.argv[1]
s = open(f).read()

if "f61_playlist_label" in s:
    print("f61: AttachmentsHelper уже пропатчен")
    sys.exit(0)

# displayLink: .locals 2 (v0, v1), p2 — url, p4 — Activity (Context).
# К этому моменту v0 — строка-метка ("Ссылка"/"Опрос"/"Истории"), v1 мёртв.
anchor = """    .line 963
    :cond_1
    const-string p4, ": "
"""
inject = """    .line 963
    :cond_1
    # f61_playlist_label: для плейлиста показываем «Плейлист», а не «Ссылка»
    const-string v1, "/music/playlist"

    invoke-virtual {p2, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z

    move-result v1

    if-eqz v1, :cond_f61_pl

    sget v0, Lcom/perm/kate/R$string;->audio_playlist:I

    invoke-virtual {p4, v0}, Landroid/content/Context;->getString(I)Ljava/lang/String;

    move-result-object v0

    :cond_f61_pl
    const-string p4, ": "
"""
assert s.count(anchor) == 1, "f61: displayLink не найден"
s = s.replace(anchor, inject, 1)

open(f, "w").write(s)
print("f61 AttachmentsHelper: подпись «Плейлист» для /music/playlist")
EOF
