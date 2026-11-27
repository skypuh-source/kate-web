#!/bin/sh
# патч f62 (2026-11-26): треки плейлиста в AudioActivity2.
#
# VK web API (v5.289, audio.getPlaylistById) отдаёт только метаданные
# плейлиста (id, owner_id, title, count, access_key, photo), но БЕЗ массива
# `audios`. Kate 133.11 рассчитывает, что `audios` там есть: AudioFragment
# вызывает getPlaylistById, в колбэке кладёт AudioAlbum в поле playlist и
# больше ничего не грузит — список остаётся пустым. Проверено на
# /music/playlist/16178728_85380604 («CHILL утро», 21 трек): запрос
# audio.getPlaylistById уходит, audio.get — нет, экран пустой.
#
# Штатный путь загрузки треков в AudioFragment уже есть: downloadAudios()
# с offset 0 вызывает Session.getAudio(uid, group=null, album_id,
# ids=null, count=200, offset, access_key, callback, activity), т.е.
# audio.get по album_id/owner_id/access_key. Для плейлиста album_id и
# access_key уже заполнены из интента (AudioActivity2 → Bundle).
#
# Фикс: в колбэке getPlaylistById (AudioFragment$29.ready) после сохранения
# playlist вызываем downloadAudios(0, callback) — дальше работает обычный
# колбэк фрагмента, который заполняет список и рисует его.
K="$(dirname "$0")/../"
cd "$K" || exit 1

F=decode/smali/com/perm/kate/AudioFragment\$29.smali

python3 - "$F" <<'EOF'
import sys

f = sys.argv[1]
s = open(f).read()

if "f62_playlist_tracks" in s:
    print("f62: AudioFragment$29 уже пропатчен")
    sys.exit(0)

old = """.method public ready(Ljava/lang/Object;)V
    .locals 1

    if-eqz p1, :cond_0

    .line 1227
    iget-object v0, p0, Lcom/perm/kate/AudioFragment$29;->this$0:Lcom/perm/kate/AudioFragment;

    check-cast p1, Lcom/perm/kate/api/AudioAlbum;

    iput-object p1, v0, Lcom/perm/kate/AudioFragment;->playlist:Lcom/perm/kate/api/AudioAlbum;

    :cond_0
    return-void
.end method
"""

new = """.method public ready(Ljava/lang/Object;)V
    .locals 3

    const/4 v0, 0x0

    if-eqz p1, :cond_0

    .line 1227
    iget-object v0, p0, Lcom/perm/kate/AudioFragment$29;->this$0:Lcom/perm/kate/AudioFragment;

    check-cast p1, Lcom/perm/kate/api/AudioAlbum;

    iput-object p1, v0, Lcom/perm/kate/AudioFragment;->playlist:Lcom/perm/kate/api/AudioAlbum;

    :cond_0
    # f62_playlist_tracks: в ответе web-API нет audios — грузим треки штатно
    if-eqz v0, :done_f62

    const/4 v1, 0x0

    iget-object v2, v0, Lcom/perm/kate/AudioFragment;->callback:Lcom/perm/kate/session/Callback;

    invoke-virtual {v0, v1, v2}, Lcom/perm/kate/AudioFragment;->downloadAudios(ILcom/perm/kate/session/Callback;)V

    :done_f62
    return-void
.end method
"""

assert s.count(old) == 1, "f62: AudioFragment$29.ready не найден"
s = s.replace(old, new, 1)
open(f, "w").write(s)
print("f62 AudioFragment: догрузка треков плейлиста через downloadAudios")
EOF
