#!/bin/sh
# патч f50 (2026-10-29): автообновление ленты.
#
# 1) Чиним галочку «Обновлять при запуске» (key_refresh_news).
#    Сейчас она не работает: NewsFragment.onCreate сбрасывает статический
#    redisplay_data = false, а NewsFragment.onStart обновляет ленту только при
#    redisplay_data = true. Выставляет флаг только Settings$22, то есть лишь в
#    момент изменения настройки. isRefreshNewsOnStartEnabled() вызывается один
#    раз — в лог-строке loadMore — и на поведение не влияет.
#
#    Решение: process-scoped флаг NewsStartupRefresh.done. При первом onStart
#    после старта процесса лента обновляется тихо (manual = false): старые посты
#    остаются на экране, сверху появляется снекбар «N новых постов».
#
# 2) Добавляем периодическое обновление, пока вкладка «Новости» активна.
#    Интервал — key_news_refresh_interval (0/5/10/30 минут, по умолчанию 0).
#    Таймер живёт в handler фрагмента, отменяется в onStop, а тик проверяет,
#    что вкладка действительно текущая и список прокручен в начало: иначе
#    обновление дёргало бы ленту у пользователя, читающего другой раздел.
#
# 3) refreshInThread(false) становится действительно тихим: прогресс-бар
#    показывается только при manual = true. Раньше NewsFragment$1.run всегда
#    вызывал showProgressBar(true).
#
# Новые классы (пакет com.perm.kate, поэтому пишутся по точному пути):
#   • NewsStartupRefresh    — флаг «стартовое обновление уже было»;
#   • NewsAutoRefresh       — Runnable периодического обновления;
#   • NewsIntervalPreference — ListPreference с вариантами интервала без
#     новых ресурсов (entries/entryValues задаются в конструкторе).
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
import os

MARK = "f50_news_refresh"
BASE = "decode/smali/com/perm/kate/"

STARTUP = '''.class public final Lcom/perm/kate/NewsStartupRefresh;
.super Ljava/lang/Object;
.source "NewsStartupRefresh.java"


# static fields
.field private static done:Z


# direct methods
.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static markDone()V
    .locals 1

    const/4 v0, 0x1

    sput-boolean v0, Lcom/perm/kate/NewsStartupRefresh;->done:Z

    return-void
.end method

.method public static shouldRefresh()Z
    .locals 3

    # f50_news_refresh: стартовое обновление выполняется один раз за процесс
    sget-boolean v0, Lcom/perm/kate/NewsStartupRefresh;->done:Z

    if-eqz v0, :cond_off

    const/4 v0, 0x0

    return v0

    :cond_off
    sget-object v0, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    invoke-static {v0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;

    move-result-object v0

    const-string v1, "key_refresh_news"

    const/4 v2, 0x1

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getBoolean(Ljava/lang/String;Z)Z

    move-result v0

    return v0
.end method
'''

AUTO = '''.class public final Lcom/perm/kate/NewsAutoRefresh;
.super Ljava/lang/Object;
.source "NewsAutoRefresh.java"

# interfaces
.implements Ljava/lang/Runnable;


# static fields
.field private static pending:Lcom/perm/kate/NewsAutoRefresh;


# instance fields
.field private final fragment:Lcom/perm/kate/NewsFragment;


# direct methods
.method public constructor <init>(Lcom/perm/kate/NewsFragment;)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lcom/perm/kate/NewsAutoRefresh;->fragment:Lcom/perm/kate/NewsFragment;

    return-void
.end method

.method public static cancel(Lcom/perm/kate/NewsFragment;)V
    .locals 2

    sget-object v0, Lcom/perm/kate/NewsAutoRefresh;->pending:Lcom/perm/kate/NewsAutoRefresh;

    if-nez v0, :cond_done

    return-void

    :cond_done
    iget-object v1, p0, Lcom/perm/kate/NewsFragment;->handler:Landroid/os/Handler;

    if-eqz v1, :cond_clear

    invoke-virtual {v1, v0}, Landroid/os/Handler;->removeCallbacks(Ljava/lang/Runnable;)V

    :cond_clear
    const/4 v0, 0x0

    sput-object v0, Lcom/perm/kate/NewsAutoRefresh;->pending:Lcom/perm/kate/NewsAutoRefresh;

    return-void
.end method

.method public static schedule(Lcom/perm/kate/NewsFragment;)V
    .locals 4

    invoke-static {p0}, Lcom/perm/kate/NewsAutoRefresh;->cancel(Lcom/perm/kate/NewsFragment;)V

    sget-object v0, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    invoke-static {v0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;

    move-result-object v0

    const-string v1, "key_news_refresh_interval"

    # ListPreference хранит значение строкой, поэтому читаем String и парсим
    const-string v2, "0"

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getString(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;

    move-result-object v0

    invoke-static {v0}, Ljava/lang/Integer;->parseInt(Ljava/lang/String;)I

    move-result v0

    if-gtz v0, :cond_none

    return-void

    :cond_none
    const/16 v1, 0x3c

    mul-int/2addr v0, v1

    const/16 v1, 0x3e8

    mul-int/2addr v0, v1

    int-to-long v0, v0

    iget-object v3, p0, Lcom/perm/kate/NewsFragment;->handler:Landroid/os/Handler;

    if-eqz v3, :cond_skip

    new-instance v2, Lcom/perm/kate/NewsAutoRefresh;

    invoke-direct {v2, p0}, Lcom/perm/kate/NewsAutoRefresh;-><init>(Lcom/perm/kate/NewsFragment;)V

    sput-object v2, Lcom/perm/kate/NewsAutoRefresh;->pending:Lcom/perm/kate/NewsAutoRefresh;

    invoke-virtual {v3, v2, v0, v1}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z

    :cond_skip
    return-void
.end method


# virtual methods
.method public run()V
    .locals 4

    iget-object v0, p0, Lcom/perm/kate/NewsAutoRefresh;->fragment:Lcom/perm/kate/NewsFragment;

    invoke-virtual {v0}, Landroidx/fragment/app/Fragment;->isAdded()Z

    move-result v1

    if-eqz v1, :cond_skip

    invoke-virtual {v0}, Landroidx/fragment/app/Fragment;->getActivity()Landroidx/fragment/app/FragmentActivity;

    move-result-object v1

    if-eqz v1, :cond_skip

    instance-of v2, v1, Lcom/perm/kate/MainActivity;

    if-eqz v2, :cond_skip

    check-cast v1, Lcom/perm/kate/MainActivity;

    iget-object v2, v1, Lcom/perm/kate/MainActivity;->mPager:Landroidx/viewpager/widget/ViewPager;

    if-eqz v2, :cond_skip

    invoke-virtual {v2}, Landroidx/viewpager/widget/ViewPager;->getCurrentItem()I

    move-result v2

    iget-object v3, v1, Lcom/perm/kate/MainActivity;->tabs:Lcom/perm/kate/tabs/TabsInfo;

    invoke-virtual {v3, v2}, Lcom/perm/kate/tabs/TabsInfo;->get(I)Lcom/perm/kate/tabs/TabInfo;

    move-result-object v2

    iget-object v2, v2, Lcom/perm/kate/tabs/TabInfo;->fragment:Lcom/perm/kate/BaseFragment;

    if-eq v2, v0, :cond_current

    goto :cond_skip

    :cond_current
    iget-object v2, v0, Lcom/perm/kate/NewsFragment;->lv_posts_news_list:Landroid/widget/ListView;

    if-eqz v2, :cond_skip

    invoke-virtual {v2}, Landroid/widget/ListView;->getFirstVisiblePosition()I

    move-result v2

    if-eqz v2, :cond_top

    goto :cond_skip

    :cond_top
    const/4 v1, 0x0

    invoke-virtual {v0, v1}, Lcom/perm/kate/NewsFragment;->refreshInThread(Z)V

    :cond_skip
    invoke-static {v0}, Lcom/perm/kate/NewsAutoRefresh;->schedule(Lcom/perm/kate/NewsFragment;)V

    return-void
.end method
'''

INTERVAL = '''.class public final Lcom/perm/kate/NewsIntervalPreference;
.super Landroid/preference/ListPreference;
.source "NewsIntervalPreference.java"


# direct methods
.method public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;)V
    .locals 3

    invoke-direct {p0, p1, p2}, Landroid/preference/ListPreference;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;)V

    # f50_news_refresh: варианты интервала задаём кодом, без новых ресурсов
    const/4 v0, 0x4

    new-array v1, v0, [Ljava/lang/CharSequence;

    const/4 v2, 0x0

    const-string v0, "Выключено"

    aput-object v0, v1, v2

    const/4 v2, 0x1

    const-string v0, "5 минут"

    aput-object v0, v1, v2

    const/4 v2, 0x2

    const-string v0, "10 минут"

    aput-object v0, v1, v2

    const/4 v2, 0x3

    const-string v0, "30 минут"

    aput-object v0, v1, v2

    invoke-virtual {p0, v1}, Landroid/preference/ListPreference;->setEntries([Ljava/lang/CharSequence;)V

    const/4 v0, 0x4

    new-array v1, v0, [Ljava/lang/CharSequence;

    const/4 v2, 0x0

    const-string v0, "0"

    aput-object v0, v1, v2

    const/4 v2, 0x1

    const-string v0, "5"

    aput-object v0, v1, v2

    const/4 v2, 0x2

    const-string v0, "10"

    aput-object v0, v1, v2

    const/4 v2, 0x3

    const-string v0, "30"

    aput-object v0, v1, v2

    invoke-virtual {p0, v1}, Landroid/preference/ListPreference;->setEntryValues([Ljava/lang/CharSequence;)V

    return-void
.end method
'''

NEW_ONSTART = '''.method public onStart()V
    .locals 2

    # f50_news_refresh: onStart
    .line 1042
    invoke-super {p0}, Lcom/perm/kate/BaseFragment;->onStart()V

    .line 1043
    sget-boolean v0, Lcom/perm/kate/NewsFragment;->redisplay_data:Z

    if-eqz v0, :cond_0

    const/4 v0, 0x0

    .line 1044
    sput-boolean v0, Lcom/perm/kate/NewsFragment;->redisplay_data:Z

    .line 1045
    invoke-virtual {p0}, Lcom/perm/kate/NewsFragment;->getSelectedFilterId()I

    move-result v0

    invoke-virtual {p0, v0}, Lcom/perm/kate/NewsFragment;->initFilterParams(I)V

    const/4 v0, 0x1

    .line 1046
    invoke-virtual {p0, v0}, Lcom/perm/kate/NewsFragment;->refreshInThread(Z)V

    .line 1047
    const-string v0, "redisplay_data"

    invoke-static {v0}, Lcom/perm/kate/NewsFragment;->reportNewsApi(Ljava/lang/String;)V

    .line 1048
    iget-object v0, p0, Lcom/perm/kate/NewsFragment;->notes:Lcom/perm/kate/NewsCursorAdapter;

    iget-object v1, p0, Lcom/perm/kate/NewsFragment;->cursor:Landroid/database/Cursor;

    invoke-virtual {v0, v1}, Landroid/widget/CursorAdapter;->changeCursor(Landroid/database/Cursor;)V

    # f50_news_refresh: ручное обновление уже произошло
    invoke-static {}, Lcom/perm/kate/NewsStartupRefresh;->markDone()V

    :cond_0
    # f50_news_refresh: тихое обновление ленты при запуске приложения
    invoke-static {}, Lcom/perm/kate/NewsStartupRefresh;->shouldRefresh()Z

    move-result v0

    if-eqz v0, :f50_no_startup

    invoke-static {}, Lcom/perm/kate/NewsStartupRefresh;->markDone()V

    invoke-virtual {p0}, Lcom/perm/kate/NewsFragment;->getSelectedFilterId()I

    move-result v0

    invoke-virtual {p0, v0}, Lcom/perm/kate/NewsFragment;->initFilterParams(I)V

    const/4 v0, 0x0

    invoke-virtual {p0, v0}, Lcom/perm/kate/NewsFragment;->refreshInThread(Z)V

    const-string v0, "startup_refresh"

    invoke-static {v0}, Lcom/perm/kate/NewsFragment;->reportNewsApi(Ljava/lang/String;)V

    :f50_no_startup
    # f50_news_refresh: периодическое обновление, пока вкладка активна
    invoke-static {p0}, Lcom/perm/kate/NewsAutoRefresh;->schedule(Lcom/perm/kate/NewsFragment;)V

    return-void
.end method'''


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, s):
    with open(path, "w", encoding="utf-8") as f:
        f.write(s)


def ensure_class(name, body):
    path = BASE + name
    if os.path.exists(path):
        if read(path) == body:
            print("f50 %s: уже существует" % name)
            return
        write(path, body)
        print("f50 %s: обновлён" % name)
        return
    write(path, body)
    print("f50 %s: создан" % name)


def replace_method(s, signature, body):
    assert s.count(signature) == 1, "f50: сигнатура %r не найдена/не уникальна" % signature
    start = s.index(signature)
    end = s.index(".end method", start) + len(".end method")
    return s[:start] + body + s[end:]


# --- 1) новые классы ----------------------------------------------------------
ensure_class("NewsStartupRefresh.smali", STARTUP)
ensure_class("NewsAutoRefresh.smali", AUTO)
ensure_class("NewsIntervalPreference.smali", INTERVAL)

# --- 2) тихий режим refreshInThread(false) -----------------------------------
p = BASE + "NewsFragment$1.smali"
s = read(p)
if MARK + ": quiet" in s:
    print("f50 NewsFragment$1: уже применён")
else:
    old = """    const/4 v1, 0x1

    invoke-virtual {v0, v1}, Lcom/perm/kate/BaseFragment;->showProgressBar(Z)V"""
    new = """    # f50_news_refresh: quiet
    iget-boolean v1, p0, Lcom/perm/kate/NewsFragment$1;->val$manual:Z

    invoke-virtual {v0, v1}, Lcom/perm/kate/BaseFragment;->showProgressBar(Z)V"""
    assert s.count(old) == 1, "f50: якорь showProgressBar не найден/не уникален"
    s = s.replace(old, new, 1)
    write(p, s)
    print("f50 NewsFragment$1: прогресс только при manual=true")

# --- 3) onStart: стартовое и периодическое обновление -------------------------
p = BASE + "NewsFragment.smali"
s = read(p)
if MARK + ": onStart" in s:
    print("f50 NewsFragment.onStart: уже применён")
else:
    s = replace_method(s, ".method public onStart()V", NEW_ONSTART)
    print("f50 NewsFragment.onStart: добавлены старт и расписание")

# --- 4) onStop: отмена таймера ------------------------------------------------
if MARK + ": onStop" in s:
    print("f50 NewsFragment.onStop: уже применён")
else:
    old = """.method public onStop()V
    .locals 1

    .line 1438
    invoke-super {p0}, Landroidx/fragment/app/Fragment;->onStop()V"""
    new = """.method public onStop()V
    .locals 1

    .line 1438
    invoke-super {p0}, Landroidx/fragment/app/Fragment;->onStop()V

    # f50_news_refresh: onStop
    invoke-static {p0}, Lcom/perm/kate/NewsAutoRefresh;->cancel(Lcom/perm/kate/NewsFragment;)V"""
    assert s.count(old) == 1, "f50: якорь onStop не найден/не уникален"
    s = s.replace(old, new, 1)
    print("f50 NewsFragment.onStop: таймер отменяется")

write(p, s)

# --- 5) настройка интервала ---------------------------------------------------
for p in ("decode/res/xml/preferences.xml", "decode/res/xml-v22/preferences.xml"):
    if not os.path.exists(p):
        continue
    s = read(p)
    if "key_news_refresh_interval" in s:
        print("f50 %s: уже применён" % p)
        continue
    anchor = ('        <CheckBoxPreference android:title="@string/new_posts_title" '
              'android:key="key_show_new_posts" android:summary="@string/new_posts_summary" '
              'android:dependency="key_refresh_news" android:defaultValue="false" />\n')
    assert s.count(anchor) == 1, "f50: якорь key_show_new_posts не найден/не уникален в %s" % p
    item = ('        <com.perm.kate.NewsIntervalPreference android:title="Автообновление ленты" '
            'android:key="key_news_refresh_interval" '
            'android:summary="Периодически обновлять ленту, пока открыта вкладка" '
            'android:dialogTitle="Обновлять ленту" android:defaultValue="0" />\n')
    s = s.replace(anchor, anchor + item, 1)
    write(p, s)
    print("f50 %s: пункт интервала добавлен" % p)
PYEOF
