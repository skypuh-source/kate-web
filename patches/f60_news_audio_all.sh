#!/bin/sh
# патч f60 (2026-11-19): треки в ленте «Все».
#
# f59 добавил `audio` в фильтр newsfeed.get, но VK отдаёт audio-элементы только
# для источников «друзья/following» (проверено дампами):
#   * «Все» (source_ids не задан)            — audio нет;
#   * «Все» (friends,following,groups,pages) — audio нет;
#   * «Сообщества» (groups,pages)            — audio нет;
#   * «Друзья» (friends)                     — audio есть.
#
# Поэтому в «Все» треки не появляются. Фикс: перед записью ленты в БД делаем
# второй синхронный запрос newsfeed.get с filters=audio,ads_post и
# source_ids=friends,following (тот же Api.getNews, что и у основного канала) и
# подмешиваем items + profiles + groups в основной Newsfeed. Дальше всё идёт
# штатным путём: displayNewPosts → deleteAndCreateNews, поэтому дедупликация не
# нужна — лента перезаписывается целиком (`news` удаляется по account_id).
#
# Порядок важен: лента в БД читается `order by n._id` (порядок вставки), поэтому
# audio-элементы вставляются в items по убыванию date, а не в конец списка.
#
# Условия:
#   * только вкладка «Все» (getSelectedFilterId() == 0), чтобы не подмешивать
#     треки в «Фотографии»/«Сообщества»;
#   * только при refresh (NewsFragment$2.ready), не при loadMore: у audio-ленты
#     свой курсор start_from, подставлять в него курсор постов нельзя.
#
# Ошибка второго запроса не должна ломать ленту: блок обёрнут в собственный
# try/catch, при исключении показываем основной ответ.
K="$(dirname "$0")/../"
cd "$K" || exit 1

F=decode/smali/com/perm/kate/NewsFragment\$2.smali

python3 - "$F" <<'EOF'
import sys

f = sys.argv[1]
s = open(f).read()

if "f60_news_audio_merge" in s:
    print("f60: уже применён")
    sys.exit(0)

old_locals = """.method public ready(Ljava/lang/Object;)V
    .locals 3
"""
new_locals = """.method public ready(Ljava/lang/Object;)V
    .locals 14
"""
assert s.count(old_locals) == 1, "f60: заголовок ready не найден/не уникален"
s = s.replace(old_locals, new_locals, 1)

anchor = """    invoke-static {v1, v2}, Lcom/perm/kate/NewsFragment;->-$$Nest$mcheckAdCount(Lcom/perm/kate/NewsFragment;Ljava/util/ArrayList;)Ljava/util/ArrayList;

    move-result-object v1

    iput-object v1, p1, Lcom/perm/kate/api/Newsfeed;->items:Ljava/util/ArrayList;
"""

inject = """    invoke-static {v1, v2}, Lcom/perm/kate/NewsFragment;->-$$Nest$mcheckAdCount(Lcom/perm/kate/NewsFragment;Ljava/util/ArrayList;)Ljava/util/ArrayList;

    move-result-object v1

    iput-object v1, p1, Lcom/perm/kate/api/Newsfeed;->items:Ljava/util/ArrayList;

    # f60_news_audio_merge: подмешиваем ленту треков в «Все»
    :try_start_f60
    iget-object v1, p0, Lcom/perm/kate/NewsFragment$2;->this$0:Lcom/perm/kate/NewsFragment;

    invoke-virtual {v1}, Lcom/perm/kate/NewsFragment;->getSelectedFilterId()I

    move-result v1

    if-nez v1, :cond_f60_skip

    sget-object v1, Lcom/perm/kate/KApplication;->session:Lcom/perm/kate/session/Session;

    if-nez v1, :cond_f60_api

    goto :goto_f60_done

    :cond_f60_api
    iget-object v1, v1, Lcom/perm/kate/session/Session;->api:Lcom/perm/kate/api/Api;

    if-nez v1, :cond_f60_dev

    goto :goto_f60_done

    :cond_f60_dev
    sget-object v12, Lcom/perm/kate/session/Session;->device_info:Ljava/lang/String;

    if-nez v12, :cond_f60_call

    invoke-static {}, Lcom/perm/kate/Helper;->getDeviceInfo()Ljava/lang/String;

    move-result-object v12

    sput-object v12, Lcom/perm/kate/session/Session;->device_info:Ljava/lang/String;

    :cond_f60_call
    const/4 v2, 0x0

    sget v3, Lcom/perm/kate/NewsFragment;->count:I

    int-to-long v3, v3

    const/4 v5, 0x0

    const/4 v6, 0x0

    const-string v7, "friends,following"

    const-string v8, "audio,ads_post"

    const/4 v9, 0x0

    const/4 v10, 0x0

    const/4 v11, 0x0

    invoke-virtual/range {v1 .. v12}, Lcom/perm/kate/api/Api;->getNews(Ljava/lang/Long;JLjava/lang/Long;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Integer;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Lcom/perm/kate/api/Newsfeed;

    move-result-object v1

    if-nez v1, :cond_f60_items

    goto :goto_f60_done

    :cond_f60_items
    iget-object v2, v1, Lcom/perm/kate/api/Newsfeed;->items:Ljava/util/ArrayList;

    if-eqz v2, :cond_f60_skip

    invoke-virtual {v2}, Ljava/util/ArrayList;->isEmpty()Z

    move-result v3

    if-eqz v3, :cond_f60_add

    goto :goto_f60_done

    # вставка audio-элементов в items по убыванию date
    :cond_f60_add
    iget-object v3, p1, Lcom/perm/kate/api/Newsfeed;->items:Ljava/util/ArrayList;

    invoke-virtual {v2}, Ljava/util/ArrayList;->size()I

    move-result v4

    const/4 v5, 0x0

    :goto_f60_outer
    if-ge v5, v4, :cond_f60_profiles

    invoke-virtual {v2, v5}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;

    move-result-object v6

    check-cast v6, Lcom/perm/kate/api/NewsItem;

    iget-wide v7, v6, Lcom/perm/kate/api/NewsItem;->date:J

    invoke-virtual {v3}, Ljava/util/ArrayList;->size()I

    move-result v9

    const/4 v10, 0x0

    :goto_f60_inner
    if-ge v10, v9, :cond_f60_insert

    invoke-virtual {v3, v10}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;

    move-result-object v11

    check-cast v11, Lcom/perm/kate/api/NewsItem;

    iget-wide v12, v11, Lcom/perm/kate/api/NewsItem;->date:J

    cmp-long v11, v12, v7

    if-ltz v11, :cond_f60_insert

    add-int/lit8 v10, v10, 0x1

    goto :goto_f60_inner

    :cond_f60_insert
    invoke-virtual {v3, v10, v6}, Ljava/util/ArrayList;->add(ILjava/lang/Object;)V

    add-int/lit8 v5, v5, 0x1

    goto :goto_f60_outer

    :cond_f60_profiles
    iget-object v2, v1, Lcom/perm/kate/api/Newsfeed;->profiles:Ljava/util/ArrayList;

    if-eqz v2, :cond_f60_groups

    iget-object v3, p1, Lcom/perm/kate/api/Newsfeed;->profiles:Ljava/util/ArrayList;

    invoke-virtual {v3, v2}, Ljava/util/ArrayList;->addAll(Ljava/util/Collection;)Z

    :cond_f60_groups
    iget-object v2, v1, Lcom/perm/kate/api/Newsfeed;->groups:Ljava/util/ArrayList;

    if-eqz v2, :cond_f60_skip

    iget-object v3, p1, Lcom/perm/kate/api/Newsfeed;->groups:Ljava/util/ArrayList;

    invoke-virtual {v3, v2}, Ljava/util/ArrayList;->addAll(Ljava/util/Collection;)Z

    :cond_f60_skip
    :try_end_f60
    .catch Ljava/lang/Throwable; {:try_start_f60 .. :try_end_f60} :catch_f60

    goto :goto_f60_done

    :catch_f60
    move-exception v0

    :goto_f60_done
    const/4 v0, 0x0
"""

assert s.count(anchor) == 1, "f60: якорь checkAdCount не найден/не уникален"
s = s.replace(anchor, inject, 1)
open(f, "w").write(s)
print("f60 NewsFragment$2: audio-лента подмешивается в «Все»")
EOF

# 2. Порядок в ленте. Курсор новостей читался `order by n._id` — то есть в
# порядке вставки. Раньше это совпадало с порядком ответа VK (date desc), но
# после слияния audio-элементов и догрузки старых постов вставка перестаёт
# быть хронологической, и лента идёт «вразброс». Сортируем по дате.
F=decode/smali/com/perm/kate/db/DataHelper.smali
python3 - "$F" <<'EOF'
import sys

f = sys.argv[1]
s = open(f).read()

old = "AND (n.type IS NULL OR n.type <> 'ads') order by n._id\""
new = "AND (n.type IS NULL OR n.type <> 'ads') order by n.date desc, n._id desc\""

if "order by n.date desc, n._id desc" in s:
    print("f60 DataHelper: сортировка по дате уже есть")
    sys.exit(0)

assert s.count(old) == 1, "f60: запрос ленты не найден/не уникален"
s = s.replace(old, new, 1)
open(f, "w").write(s)
print("f60 DataHelper: лента сортируется по дате (date desc, _id desc)")
EOF
