#!/bin/sh
# патч f51 (2026-10-29): пункт «Воспроизвести в…» в контекстном меню аудио.
#
# Что делает:
#   • добавляет в меню аудио пункт «Воспроизвести в» (строка play_with уже есть
#     в ресурсах, id пункта 0x13 — свободен, packed-switch занимает 0xb..0x12);
#   • если mp3 уже лежит в кэше (AudioCacheManager.cacheDir()/<owner_id>_<aid>.mp3),
#     открывает системный chooser через FileProvider (authority
#     com.perm.kate.provider, provider_paths уже содержит external-path ".");
#   • если файла нет — только тост «Файл не в кэше»: докачивание из этого
#     пункта отключено (автокэш при прослушивании остаётся в f53);
#   • ошибки FileProvider и отсутствие плеера — тост, без краша.
#
# Ограничения:
#   • если папка кэша настроена на съёмную SD-карту, FileProvider её не покрывает
#     (external-path указывает на основное внешнее хранилище) — в этом случае
#     открываем исходный URL через ACTION_VIEW;
#   • на API 16–20 флаг FLAG_GRANT_READ_URI_PERMISSION выставляется и на
#     внутренний Intent, и на chooser.
#
# Новые классы пишутся по точному пути, потому что пакет не com/perm/kate/api:
#   • AudioPlayWith      — cachedFile / open / playWith.
#
# Откат: пересобрать из orig/ или удалить класс и две вставки в
# AudioClickHelper.smali / AudioClickHelper$3.smali.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
import os

MARK = "f51_play_with"
BASE = "decode/smali/com/perm/kate/"

PLAYWITH = '''.class public final Lcom/perm/kate/AudioPlayWith;
.super Ljava/lang/Object;
.source "AudioPlayWith.java"


# static fields
.field private static final HANDLER:Landroid/os/Handler;


# direct methods
.method static constructor <clinit>()V
    .locals 2

    new-instance v0, Landroid/os/Handler;

    invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;

    move-result-object v1

    invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V

    sput-object v0, Lcom/perm/kate/AudioPlayWith;->HANDLER:Landroid/os/Handler;

    return-void
.end method

.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static cachedFile(Lcom/perm/kate/api/Audio;)Ljava/io/File;
    .locals 4

    invoke-static {}, Lcom/perm/kate/audio_cache/AudioCacheManager;->cacheDir()Ljava/io/File;

    move-result-object v0

    if-eqz v0, :f51_cf_null

    new-instance v1, Ljava/lang/StringBuilder;

    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V

    iget-wide v2, p0, Lcom/perm/kate/api/Audio;->owner_id:J

    invoke-virtual {v1, v2, v3}, Ljava/lang/StringBuilder;->append(J)Ljava/lang/StringBuilder;

    const/16 v2, 0x5f

    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(C)Ljava/lang/StringBuilder;

    iget-wide v2, p0, Lcom/perm/kate/api/Audio;->aid:J

    invoke-virtual {v1, v2, v3}, Ljava/lang/StringBuilder;->append(J)Ljava/lang/StringBuilder;

    const-string v2, ".mp3"

    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v1

    new-instance v2, Ljava/io/File;

    invoke-direct {v2, v0, v1}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V

    return-object v2

    :f51_cf_null
    const/4 v0, 0x0

    return-object v0
.end method

.method public static close(Ljava/io/Closeable;)V
    .locals 1

    if-eqz p0, :f51_close_done

    :try_start_0
    invoke-interface {p0}, Ljava/io/Closeable;->close()V
    :try_end_0
    .catch Ljava/io/IOException; {:try_start_0 .. :try_end_0} :catch_0

    :f51_close_done
    return-void

    :catch_0
    move-exception v0

    goto :f51_close_done
.end method



.method public static open(Landroid/app/Activity;Lcom/perm/kate/api/Audio;Ljava/io/File;)V
    .locals 4

    if-eqz p0, :f51_open_ret

    const/4 v0, 0x0

    if-eqz p2, :f51_open_url

    invoke-virtual {p2}, Ljava/io/File;->exists()Z

    move-result v1

    if-eqz v1, :f51_open_url

    :try_start_0
    const-string v1, "com.perm.kate.provider"

    invoke-static {p0, v1, p2}, Landroidx/core/content/FileProvider;->getUriForFile(Landroid/content/Context;Ljava/lang/String;Ljava/io/File;)Landroid/net/Uri;

    move-result-object v0
    :try_end_0
    .catch Ljava/lang/IllegalArgumentException; {:try_start_0 .. :try_end_0} :catch_0

    goto :f51_open_a1

    :catch_0
    move-exception v1

    :f51_open_url
    if-eqz p1, :f51_open_a1

    iget-object v1, p1, Lcom/perm/kate/api/Audio;->url:Ljava/lang/String;

    invoke-static {v1}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z

    move-result v2

    if-eqz v2, :f51_open_a1

    invoke-static {v1}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;

    move-result-object v0

    :f51_open_a1
    if-nez v0, :f51_open_build

    const-string v1, "Не удалось открыть файл"

    invoke-static {p0, v1}, Lcom/perm/kate/AudioPlayWith;->toast(Landroid/app/Activity;Ljava/lang/String;)V

    return-void

    :f51_open_build
    new-instance v1, Landroid/content/Intent;

    const-string v2, "android.intent.action.VIEW"

    invoke-direct {v1, v2}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V

    const-string v2, "audio/*"

    invoke-virtual {v1, v0, v2}, Landroid/content/Intent;->setDataAndType(Landroid/net/Uri;Ljava/lang/String;)Landroid/content/Intent;

    const/4 v2, 0x1

    invoke-virtual {v1, v2}, Landroid/content/Intent;->addFlags(I)Landroid/content/Intent;

    sget v2, Lcom/perm/kate/R$string;->play_with:I

    invoke-virtual {p0, v2}, Landroid/app/Activity;->getString(I)Ljava/lang/String;

    move-result-object v2

    invoke-static {v1, v2}, Landroid/content/Intent;->createChooser(Landroid/content/Intent;Ljava/lang/CharSequence;)Landroid/content/Intent;

    move-result-object v1

    const/4 v2, 0x1

    invoke-virtual {v1, v2}, Landroid/content/Intent;->addFlags(I)Landroid/content/Intent;

    :try_start_1
    invoke-virtual {p0, v1}, Landroid/app/Activity;->startActivity(Landroid/content/Intent;)V
    :try_end_1
    .catch Landroid/content/ActivityNotFoundException; {:try_start_1 .. :try_end_1} :catch_1

    return-void

    :catch_1
    move-exception v1

    const-string v1, "Нет приложения для воспроизведения"

    invoke-static {p0, v1}, Lcom/perm/kate/AudioPlayWith;->toast(Landroid/app/Activity;Ljava/lang/String;)V

    return-void

    :f51_open_ret
    return-void
.end method

.method public static playWith(Landroid/app/Activity;Lcom/perm/kate/api/Audio;)V
    .locals 2

    if-eqz p1, :f51_pw_ret

    if-eqz p0, :f51_pw_ret

    invoke-static {p1}, Lcom/perm/kate/AudioPlayWith;->cachedFile(Lcom/perm/kate/api/Audio;)Ljava/io/File;

    move-result-object v0

    if-eqz v0, :f51_pw_nocache

    invoke-virtual {v0}, Ljava/io/File;->exists()Z

    move-result v1

    if-eqz v1, :f51_pw_nocache

    invoke-static {p0, p1, v0}, Lcom/perm/kate/AudioPlayWith;->open(Landroid/app/Activity;Lcom/perm/kate/api/Audio;Ljava/io/File;)V

    return-void

    :f51_pw_nocache
    const-string v0, "Файл не в кэше"

    invoke-static {p0, v0}, Lcom/perm/kate/AudioPlayWith;->toast(Landroid/app/Activity;Ljava/lang/String;)V

    return-void

    :f51_pw_ret
    return-void
.end method

.method public static post(Ljava/lang/Runnable;)V
    .locals 1

    sget-object v0, Lcom/perm/kate/AudioPlayWith;->HANDLER:Landroid/os/Handler;

    invoke-virtual {v0, p0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z

    return-void
.end method

.method public static toast(Landroid/app/Activity;Ljava/lang/String;)V
    .locals 2

    if-eqz p0, :f51_toast_ret

    const/4 v0, 0x0

    invoke-static {p0, p1, v0}, Landroid/widget/Toast;->makeText(Landroid/content/Context;Ljava/lang/CharSequence;I)Landroid/widget/Toast;

    move-result-object v0

    invoke-virtual {v0}, Landroid/widget/Toast;->show()V

    return-void

    :f51_toast_ret
    return-void
.end method
'''

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
            print("f51 %s: уже существует" % name)
            return
        write(path, body)
        print("f51 %s: обновлён" % name)
        return
    write(path, body)
    print("f51 %s: создан" % name)


# --- 1) новые классы ----------------------------------------------------------
ensure_class("AudioPlayWith.smali", PLAYWITH)

# --- 2) пункт меню ------------------------------------------------------------
p = BASE + "AudioClickHelper.smali"
s = read(p)
if MARK + ": menu" in s:
    print("f51 AudioClickHelper: пункт меню уже добавлен")
else:
    anchor = """    invoke-direct {v0, v1, v4}, Lcom/perm/kate/MenuItemDetails;-><init>(II)V

    invoke-virtual {v2, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    const/4 v13, 0x1"""
    assert s.count(anchor) == 1, "f51: якорь первого пункта меню не найден/не уникален"
    item = """    invoke-direct {v0, v1, v4}, Lcom/perm/kate/MenuItemDetails;-><init>(II)V

    invoke-virtual {v2, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    # f51_play_with: menu
    new-instance v0, Lcom/perm/kate/MenuItemDetails;

    sget v1, Lcom/perm/kate/R$string;->play_with:I

    const/16 v4, 0x13

    invoke-direct {v0, v1, v4}, Lcom/perm/kate/MenuItemDetails;-><init>(II)V

    invoke-virtual {v2, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    const/4 v13, 0x1"""
    s = s.replace(anchor, item, 1)
    write(p, s)
    print("f51 AudioClickHelper: пункт «Воспроизвести в» добавлен")

# --- 3) обработка пункта ------------------------------------------------------
p = BASE + "AudioClickHelper$3.smali"
s = read(p)
if MARK + ": click" in s:
    print("f51 AudioClickHelper$3: обработка уже добавлена")
else:
    anchor = """    iget p1, p1, Lcom/perm/kate/MenuItemDetails;->code:I

    const/4 p2, 0x0"""
    assert s.count(anchor) == 1, "f51: якорь onClick не найден/не уникален"
    new = """    iget p1, p1, Lcom/perm/kate/MenuItemDetails;->code:I

    # f51_play_with: click
    const/16 p2, 0x13

    if-ne p1, p2, :f51_not_play_with

    iget-object p1, p0, Lcom/perm/kate/AudioClickHelper$3;->this$0:Lcom/perm/kate/AudioClickHelper;

    iget-object p1, p1, Lcom/perm/kate/AudioClickHelper;->context:Lcom/perm/kate/BaseActivity;

    iget-object p2, p0, Lcom/perm/kate/AudioClickHelper$3;->val$a:Lcom/perm/kate/api/Audio;

    invoke-static {p1, p2}, Lcom/perm/kate/AudioPlayWith;->playWith(Landroid/app/Activity;Lcom/perm/kate/api/Audio;)V

    return-void

    :f51_not_play_with
    const/4 p2, 0x0"""
    s = s.replace(anchor, new, 1)
    write(p, s)
    print("f51 AudioClickHelper$3: обработка 0x13 добавлена")

# --- 4) меню подкаста: тот же пункт -------------------------------------------
p = BASE + "AudioClickHelper.smali"
s = read(p)
if MARK + ": podcast_menu" in s:
    print("f51 AudioClickHelper (подкаст): пункт уже добавлен")
else:
    anchor = """    sget v1, Lcom/perm/kate/R$string;->label_menu_play_audio:I

    const/4 v3, 0x0

    invoke-direct {v0, v1, v3}, Lcom/perm/kate/MenuItemDetails;-><init>(II)V

    invoke-virtual {v2, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z"""
    assert s.count(anchor) == 1, "f51: якорь меню подкаста не найден/не уникален"
    item = anchor + """

    # f51_play_with: podcast_menu
    new-instance v0, Lcom/perm/kate/MenuItemDetails;

    sget v1, Lcom/perm/kate/R$string;->play_with:I

    const/16 v3, 0x13

    invoke-direct {v0, v1, v3}, Lcom/perm/kate/MenuItemDetails;-><init>(II)V

    invoke-virtual {v2, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z"""
    s = s.replace(anchor, item, 1)
    write(p, s)
    print("f51 AudioClickHelper (подкаст): пункт «Воспроизвести в» добавлен")

# --- 5) обработка пункта в меню подкаста --------------------------------------
p = BASE + "AudioClickHelper$4.smali"
s = read(p)
if MARK + ": podcast_click" in s:
    print("f51 AudioClickHelper$4: обработка уже добавлена")
else:
    anchor = """    iget p1, p1, Lcom/perm/kate/MenuItemDetails;->code:I

    if-eqz p1, :cond_4"""
    assert s.count(anchor) == 1, "f51: якорь onClick подкаста не найден/не уникален"
    new = """    iget p1, p1, Lcom/perm/kate/MenuItemDetails;->code:I

    # f51_play_with: podcast_click
    const/16 p2, 0x13

    if-ne p1, p2, :f51_podcast_continue

    iget-object p1, p0, Lcom/perm/kate/AudioClickHelper$4;->this$0:Lcom/perm/kate/AudioClickHelper;

    iget-object p1, p1, Lcom/perm/kate/AudioClickHelper;->context:Lcom/perm/kate/BaseActivity;

    iget-object p2, p0, Lcom/perm/kate/AudioClickHelper$4;->val$a:Lcom/perm/kate/api/Audio;

    invoke-static {p1, p2}, Lcom/perm/kate/AudioPlayWith;->playWith(Landroid/app/Activity;Lcom/perm/kate/api/Audio;)V

    return-void

    :f51_podcast_continue
    if-eqz p1, :cond_4"""
    s = s.replace(anchor, new, 1)
    write(p, s)
    print("f51 AudioClickHelper$4: обработка 0x13 добавлена")
PYEOF
