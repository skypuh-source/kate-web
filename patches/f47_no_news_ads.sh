#!/bin/sh
# патч f47 (2026-10-27): убираем рекламу VK из ленты.
#
# VK на web-канале подмешивает в newsfeed.get элементы {"type":"ads", ...}.
# Приложение штатно умеет их показывать (NewsItem.parse читает ads_title,
# ads_id1/ads_id2, advertiser_info_url), а ограничитель показа включается только
# при наличии preference "mna". В релизном version.json поля "mna" нет, поэтому
# min_non_ad_count=0 и реклама проходит без прореживания.
#
# Патч вырезает рекламные элементы на трёх уровнях:
#   1) Newsfeed.parse — элементы "ads" вообще не попадают в модель и в ленту;
#   2) NewsFragment.checkAdCount — страховка для уже загруженных ответов и
#      ответов, разобранных другими путями: "ads" всегда пропускается;
#   3) DataHelper.createNewsItem — рекламные элементы не пишутся в БД.
# Дополнительно DataHelper.fetchPostNews не выбирает ранее закэшированные
# строки type='ads', поэтому старая реклама исчезает из ленты сразу после
# обновления, без очистки пользовательской БД.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'EOF'
import sys

MARK = "f47_no_news_ads"

def read(path):
    with open(path) as f:
        return f.read()

def write(path, s):
    with open(path, "w") as f:
        f.write(s)

# --- 1) Newsfeed.parse: не разбирать элементы type="ads" -----------------------
p = "decode/smali/com/perm/kate/api/Newsfeed.smali"
s = read(p)
if MARK in s:
    print("f47 Newsfeed: уже применён")
else:
    old = '''    move-result-object v8

    .line 40
    const-string v9, "friends_recomm"'''
    new = '''    move-result-object v8

    # f47_no_news_ads: skip ads
    const-string v9, "ads"

    invoke-virtual {v9, v8}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v9

    if-nez v9, :goto_1

    .line 40
    const-string v9, "friends_recomm"'''
    assert s.count(old) == 1, "f47 Newsfeed: якорь не найден/не уникален"
    s = s.replace(old, new, 1)
    write(p, s)
    print("f47 Newsfeed: элементы ads пропускаются")

# --- 2) NewsFragment.checkAdCount: всегда пропускать ads ----------------------
p = "decode/smali/com/perm/kate/NewsFragment.smali"
s = read(p)
if MARK in s:
    print("f47 NewsFragment: уже применён")
else:
    old = '''    if-eqz v5, :cond_0

    .line 281
    iget-short v6, p0, Lcom/perm/kate/NewsFragment;->non_ad_count:S

    iget-short v7, p0, Lcom/perm/kate/NewsFragment;->min_non_ad_count:S

    if-ge v6, v7, :cond_0

    goto :goto_0

    :catchall_0'''
    new = '''    # f47_no_news_ads: skip ads
    if-eqz v5, :cond_0

    goto :goto_0

    :catchall_0'''
    assert s.count(old) == 1, "f47 NewsFragment: якорь checkAdCount не найден/не уникален"
    s = s.replace(old, new, 1)
    write(p, s)
    print("f47 NewsFragment: checkAdCount пропускает ads")

# --- 3) DataHelper: не писать рекламу в БД и не читать её из кэша --------------
p = "decode/smali/com/perm/kate/db/DataHelper.smali"
s = read(p)
if MARK in s:
    print("f47 DataHelper: уже применён")
else:
    old = '''.method public createNewsItem(Lcom/perm/kate/api/NewsItem;JI)V
    .locals 2

    .line 2933'''
    new = '''.method public createNewsItem(Lcom/perm/kate/api/NewsItem;JI)V
    .locals 2

    # f47_no_news_ads: skip ads
    iget-object v0, p1, Lcom/perm/kate/api/NewsItem;->type:Ljava/lang/String;

    const-string v1, "ads"

    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :f47_not_ad

    return-void

    :f47_not_ad
    .line 2933'''
    assert s.count(old) == 1, "f47 DataHelper: якорь createNewsItem не найден/не уникален"
    s = s.replace(old, new, 1)

    old = "where n.account_id=? AND n.is_comments=? order by n._id"
    new = "where n.account_id=? AND n.is_comments=? AND (n.type IS NULL OR n.type <> 'ads') order by n._id"
    assert s.count(old) == 1, "f47 DataHelper: якорь fetchPostNews не найден/не уникален"
    s = s.replace(old, new, 1)
    write(p, s)
    print("f47 DataHelper: ads не пишутся и не читаются из БД")
EOF
