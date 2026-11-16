#!/bin/sh
# патч f53 (2026-10-29): рабочий кэш mp3 + лимит размера + автокэш.
#
# Что делает:
#   • добавляет менеджер кэша com/perm/kate/audio_cache/AudioCacheManager
#     (один worker-поток, без Service): add/fetch/remove/retry/isCached/
#     fileFor/cachedPath/usedBytes/enforceLimit/limitBytes/autoCache/attach/
#     refresh;
#   • качает mp3 по audio.url в AudioCacheManager.cacheDir() (по умолчанию
#     /.Kate/audio_cache) через .part + rename, прогресс пишет в статические
#     поля AudioCacheService, поэтому существующий AudioListAdapter показывает
#     прогресс без правок адаптера;
#   • статусы в таблице audio_cache: 1 — качается, 2 — готово, 3 — ошибка;
#     DataHelper получает setAudioCacheStatus(JJI)V, removeAudioCache(JJ)V,
#     audioCacheStatus(JJ)I;
#   • ручное скачивание из меню отключено: пункты «Добавить в кэш» /
#     «Удалить из кэша» / «Повторить» (0x14/0x15/0x16) не добавляются;
#   • PlaybackService.getAudioUri() сначала отдаёт локальный файл (Player и
#     PlayerExo понимают путь без схемы), lastModified обновляется — LRU;
#   • лимит: ползунок 0…31 (1…32 = 256 МБ…8 ГБ шаг 256 МБ, минимум 256 МБ),
#     ключ key_audio_cache_limit_mb (int, default 256); при снижении лимита
#     лишние файлы сразу удаляются, самые старые первыми; подпись значения —
#     «256 МБ» / «2 ГБ (2048 МБ)» (getSummary, поэтому видна и в списке);
#   • автокэш при прослушивании: ключ key_audio_cache_auto (default true);
#   • пункты настроек — сразу после audio_cache_dir_virtual в обоих
#     preferences.xml.
#
# Новые классы (пакет не com/perm/kate/api, поэтому пишутся по точному пути):
#   • AudioCacheManager        — статические методы и поля;
#   • AudioCacheManager$1      — Runnable скачивания;
#   • AudioCacheManager$2      — обновление списка и прогресса в UI-потоке;
#   • AudioCacheManager$4      — получение свежего URL (audio.getById) для
#                                ручного скачивания; меню отключено, класс
#                                остаётся неиспользуемым;
#   • CacheLimitPreference     — android.preference.Preference с SeekBar
#                                (SeekBarPreference появился только в API 26);
#   • CacheLimitPreference$1   — слушатель SeekBar (подпись значения);
#   • CacheLimitPreference$2   — «ОК»: сохранить и применить лимит.
#
# Ограничения:
#   • скачивание идёт через androidx.media3.datasource.DefaultHttpDataSource
#     (тот же загрузчик, что у плеера): он корректно ходит по редиректам,
#     ставит Accept-Encoding: identity и кидает исключение на не-2xx;
#     нулевой ответ считается ошибкой (статус 3), а не готовым файлом;
#   • при автокэше во время воспроизведения используется URL, который только
#     что получил плеер; отдельного обновления URL для меню больше нет;
#   • кэшируются только прямые ссылки: URL с «.m3u8» (HLS-плейлист) не
#     кэшируются, иначе подмена локальным файлом сломает воспроизведение;
#     ссылки VK CDN вида https://…okcdn.ru/?…type=2… расширения не содержат,
#     поэтому проверяется именно отсутствие «.m3u8», а не наличие «.mp3»;
#   • запись в корень внешнего хранилища на Android 11+ держится на
#     requestLegacyExternalStorage="true" при targetSdk 29; если разрешение
#     WRITE_EXTERNAL_STORAGE запрещено и /.Kate/audio_cache создать нельзя,
#     cacheDir() автоматически переключается на
#     getExternalFilesDir(null)/audio_cache (Android/data/com.perm.kate/files),
#     который доступен без разрешений; usedBytes/enforceLimit работают с тем
#     каталогом, который сейчас выбран;
#   • если папка кэша на съёмной SD-карте, FileProvider её не покрывает —
#     это ограничение f51, кэш f53 от этого не зависит;
#   • удаление во время скачивания отменяет запись: готовый .part удаляется,
#     строка из audio_cache убирается.
#
# Откат: пересобрать из orig/ либо удалить шесть новых классов, три метода в
# DataHelper, вставки в AudioClickHelper / AudioFragment / PlayerActivity /
# PlaybackService и строки настроек в двух preferences.xml.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
import os

MARK = "f53_audio_cache"
BASE = "decode/smali/com/perm/kate/"
ACACHE = BASE + "audio_cache/"

MANAGER = '''.class public final Lcom/perm/kate/audio_cache/AudioCacheManager;
.super Ljava/lang/Object;
.source "AudioCacheManager.java"


# static fields
.field public static HANDLER:Landroid/os/Handler;

.field public static PENDING:Ljava/util/Set;

.field public static adapter:Lcom/perm/kate/AudioListAdapter;

.field public static executor:Ljava/util/concurrent/ExecutorService;


# direct methods
.method static constructor <clinit>()V
    .locals 2

    invoke-static {}, Ljava/util/concurrent/Executors;->newSingleThreadExecutor()Ljava/util/concurrent/ExecutorService;

    move-result-object v0

    sput-object v0, Lcom/perm/kate/audio_cache/AudioCacheManager;->executor:Ljava/util/concurrent/ExecutorService;

    new-instance v0, Landroid/os/Handler;

    invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;

    move-result-object v1

    invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V

    sput-object v0, Lcom/perm/kate/audio_cache/AudioCacheManager;->HANDLER:Landroid/os/Handler;

    new-instance v0, Ljava/util/HashSet;

    invoke-direct {v0}, Ljava/util/HashSet;-><init>()V

    invoke-static {v0}, Ljava/util/Collections;->synchronizedSet(Ljava/util/Set;)Ljava/util/Set;

    move-result-object v0

    sput-object v0, Lcom/perm/kate/audio_cache/AudioCacheManager;->PENDING:Ljava/util/Set;

    return-void
.end method

.method public static add(Lcom/perm/kate/api/Audio;)V
    .locals 8

    if-eqz p0, :add_ret_null

    iget-object v0, p0, Lcom/perm/kate/api/Audio;->url:Ljava/lang/String;

    invoke-static {v0}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z

    move-result v0

    if-nez v0, :add_ret_empty

    iget-object v0, p0, Lcom/perm/kate/api/Audio;->url:Ljava/lang/String;

    const-string v1, ".m3u8"

    invoke-virtual {v0, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z

    move-result v0

    if-nez v0, :add_ret_m3u8

    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->isCached(Lcom/perm/kate/api/Audio;)Z

    move-result v0

    if-nez v0, :add_ret_cached

    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->key(Lcom/perm/kate/api/Audio;)Ljava/lang/String;

    move-result-object v0

    if-eqz v0, :add_ret_key

    sget-object v1, Lcom/perm/kate/audio_cache/AudioCacheManager;->PENDING:Ljava/util/Set;

    invoke-interface {v1, v0}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z

    move-result v2

    if-nez v2, :add_ret_pending

    invoke-interface {v1, v0}, Ljava/util/Set;->add(Ljava/lang/Object;)Z

    sget-object v1, Lcom/perm/kate/KApplication;->db:Lcom/perm/kate/db/DataHelper;

    if-eqz v1, :add_start

    iget-wide v2, p0, Lcom/perm/kate/api/Audio;->aid:J

    iget-wide v4, p0, Lcom/perm/kate/api/Audio;->owner_id:J

    const/4 v6, 0x1

    invoke-virtual/range {v1 .. v6}, Lcom/perm/kate/db/DataHelper;->setAudioCacheStatus(JJI)V

    :add_start
    const/4 v1, 0x1

    invoke-static {v0, v1}, Lcom/perm/kate/audio_cache/AudioCacheManager;->refresh(Ljava/lang/String;I)V

    sget-object v1, Lcom/perm/kate/audio_cache/AudioCacheManager;->executor:Ljava/util/concurrent/ExecutorService;

    new-instance v2, Lcom/perm/kate/audio_cache/AudioCacheManager$1;

    invoke-direct {v2, p0}, Lcom/perm/kate/audio_cache/AudioCacheManager$1;-><init>(Lcom/perm/kate/api/Audio;)V

    invoke-interface {v1, v2}, Ljava/util/concurrent/ExecutorService;->execute(Ljava/lang/Runnable;)V

    :add_ret
    return-void

    :add_ret_null
    return-void

    :add_ret_empty
    return-void

    :add_ret_m3u8
    return-void

    :add_ret_cached
    return-void

    :add_ret_key
    return-void

    :add_ret_pending
    return-void
.end method

.method public static attach(Lcom/perm/kate/AudioListAdapter;)V
    .locals 1

    if-eqz p0, :att_ret

    sput-object p0, Lcom/perm/kate/audio_cache/AudioCacheManager;->adapter:Lcom/perm/kate/AudioListAdapter;

    :att_ret
    return-void
.end method

.method public static autoCache(Lcom/perm/kate/api/Audio;)V
    .locals 3

    if-eqz p0, :ac_ret

    sget-object v0, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    invoke-static {v0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;

    move-result-object v0

    const-string v1, "key_audio_cache_auto"

    const/4 v2, 0x1

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getBoolean(Ljava/lang/String;Z)Z

    move-result v0

    if-eqz v0, :ac_ret

    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->add(Lcom/perm/kate/api/Audio;)V

    :ac_ret
    return-void
.end method

.method public static closeConn(Ljava/net/HttpURLConnection;)V
    .locals 1

    if-eqz p0, :cc_ret

    :try_start_0
    invoke-virtual {p0}, Ljava/net/HttpURLConnection;->disconnect()V
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catch_0

    :cc_ret
    return-void

    :catch_0
    move-exception v0

    goto :cc_ret
.end method

.method public static fail(Lcom/perm/kate/api/Audio;)V
    .locals 7

    if-eqz p0, :fail_ret

    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->key(Lcom/perm/kate/api/Audio;)Ljava/lang/String;

    move-result-object v0

    sget-object v1, Lcom/perm/kate/KApplication;->db:Lcom/perm/kate/db/DataHelper;

    if-eqz v1, :fail_ref

    iget-wide v2, p0, Lcom/perm/kate/api/Audio;->aid:J

    iget-wide v4, p0, Lcom/perm/kate/api/Audio;->owner_id:J

    const/4 v6, 0x3

    invoke-virtual/range {v1 .. v6}, Lcom/perm/kate/db/DataHelper;->setAudioCacheStatus(JJI)V

    :fail_ref
    if-eqz v0, :fail_ret

    const/4 v1, 0x3

    invoke-static {v0, v1}, Lcom/perm/kate/audio_cache/AudioCacheManager;->refresh(Ljava/lang/String;I)V

    :fail_ret
    return-void
.end method

.method public static fetch(Lcom/perm/kate/api/Audio;)V
    .locals 4

    if-eqz p0, :fetch_ret

    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->isCached(Lcom/perm/kate/api/Audio;)Z

    move-result v0

    if-nez v0, :fetch_ret

    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->key(Lcom/perm/kate/api/Audio;)Ljava/lang/String;

    move-result-object v0

    if-eqz v0, :fetch_ret

    sget-object v1, Lcom/perm/kate/audio_cache/AudioCacheManager;->PENDING:Ljava/util/Set;

    invoke-interface {v1, v0}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z

    move-result v2

    if-nez v2, :fetch_ret

    sget-object v1, Lcom/perm/kate/audio_cache/AudioCacheManager;->executor:Ljava/util/concurrent/ExecutorService;

    new-instance v2, Lcom/perm/kate/audio_cache/AudioCacheManager$4;

    invoke-direct {v2, p0}, Lcom/perm/kate/audio_cache/AudioCacheManager$4;-><init>(Lcom/perm/kate/api/Audio;)V

    invoke-interface {v1, v2}, Ljava/util/concurrent/ExecutorService;->execute(Ljava/lang/Runnable;)V

    :fetch_ret
    return-void
.end method

.method public static cachedPath(Lcom/perm/kate/api/Audio;)Ljava/lang/String;
    .locals 2

    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->fileFor(Lcom/perm/kate/api/Audio;)Ljava/io/File;

    move-result-object v0

    if-eqz v0, :cp_null

    invoke-virtual {v0}, Ljava/io/File;->exists()Z

    move-result v1

    if-eqz v1, :cp_null

    invoke-static {}, Ljava/lang/System;->currentTimeMillis()J

    move-result-wide v1

    invoke-virtual {v0, v1, v2}, Ljava/io/File;->setLastModified(J)Z

    invoke-virtual {v0}, Ljava/io/File;->getAbsolutePath()Ljava/lang/String;

    move-result-object v0

    return-object v0

    :cp_null
    const/4 v0, 0x0

    return-object v0
.end method

.method public static cacheDir()Ljava/io/File;
    .locals 3

    invoke-static {}, Lcom/perm/kate/audio_cache/AudioCache;->getCacheDir()Ljava/io/File;

    move-result-object v0

    if-eqz v0, :cd_fallback

    invoke-virtual {v0}, Ljava/io/File;->isDirectory()Z

    move-result v1

    if-nez v1, :cd_check

    invoke-virtual {v0}, Ljava/io/File;->mkdirs()Z

    :cd_check
    invoke-virtual {v0}, Ljava/io/File;->isDirectory()Z

    move-result v1

    if-eqz v1, :cd_fallback

    invoke-virtual {v0}, Ljava/io/File;->canWrite()Z

    move-result v1

    if-eqz v1, :cd_fallback

    return-object v0

    :cd_fallback
    sget-object v0, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    if-eqz v0, :cd_null

    const/4 v1, 0x0

    invoke-virtual {v0, v1}, Landroid/content/Context;->getExternalFilesDir(Ljava/lang/String;)Ljava/io/File;

    move-result-object v0

    if-eqz v0, :cd_null

    new-instance v1, Ljava/io/File;

    const-string v2, "audio_cache"

    invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V

    invoke-virtual {v1}, Ljava/io/File;->isDirectory()Z

    move-result v0

    if-nez v0, :cd_ready

    invoke-virtual {v1}, Ljava/io/File;->mkdirs()Z

    :cd_ready
    invoke-virtual {v1}, Ljava/io/File;->canWrite()Z

    move-result v0

    if-eqz v0, :cd_null

    return-object v1

    :cd_null
    const/4 v0, 0x0

    return-object v0
.end method

.method public static close(Ljava/io/Closeable;)V
    .locals 1

    if-eqz p0, :close_ret

    :try_start_0
    invoke-interface {p0}, Ljava/io/Closeable;->close()V
    :try_end_0
    .catch Ljava/io/IOException; {:try_start_0 .. :try_end_0} :catch_0

    :close_ret
    return-void

    :catch_0
    move-exception v0

    goto :close_ret
.end method

.method public static declared-synchronized enforceLimit()V
    .locals 16

    invoke-static {}, Lcom/perm/kate/audio_cache/AudioCacheManager;->limitBytes()J

    move-result-wide v0

    const-wide/16 v2, 0x0

    cmp-long v3, v0, v2

    if-lez v3, :el_done

    invoke-static {}, Lcom/perm/kate/audio_cache/AudioCacheManager;->usedBytes()J

    move-result-wide v4

    invoke-static {}, Lcom/perm/kate/audio_cache/AudioCacheManager;->cacheDir()Ljava/io/File;

    move-result-object v6

    if-eqz v6, :el_done

    :el_loop
    cmp-long v3, v4, v0

    if-lez v3, :el_done

    invoke-virtual {v6}, Ljava/io/File;->listFiles()[Ljava/io/File;

    move-result-object v7

    if-eqz v7, :el_done

    const/4 v8, 0x0

    const-wide/16 v14, 0x0

    const/4 v9, 0x0

    array-length v10, v7

    :el_scan
    if-ge v9, v10, :el_scan_done

    aget-object v11, v7, v9

    invoke-virtual {v11}, Ljava/io/File;->isFile()Z

    move-result v3

    if-eqz v3, :el_next

    invoke-virtual {v11}, Ljava/io/File;->getName()Ljava/lang/String;

    move-result-object v2

    const-string v3, ".part"

    invoke-virtual {v2, v3}, Ljava/lang/String;->endsWith(Ljava/lang/String;)Z

    move-result v2

    if-nez v2, :el_next

    invoke-virtual {v11}, Ljava/io/File;->lastModified()J

    move-result-wide v12

    if-eqz v8, :el_take

    cmp-long v3, v12, v14

    if-ltz v3, :el_take

    goto :el_next

    :el_take
    move-object v8, v11

    move-wide v14, v12

    :el_next
    add-int/lit8 v9, v9, 0x1

    goto :el_scan

    :el_scan_done
    if-eqz v8, :el_done

    invoke-virtual {v8}, Ljava/io/File;->length()J

    move-result-wide v12

    invoke-virtual {v8}, Ljava/io/File;->delete()Z

    move-result v3

    if-eqz v3, :el_done

    sub-long/2addr v4, v12

    goto :el_loop

    :el_done
    return-void
.end method

.method public static fileFor(Lcom/perm/kate/api/Audio;)Ljava/io/File;
    .locals 4

    if-eqz p0, :file_null

    invoke-static {}, Lcom/perm/kate/audio_cache/AudioCacheManager;->cacheDir()Ljava/io/File;

    move-result-object v0

    if-eqz v0, :file_null

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

    :file_null
    const/4 v0, 0x0

    return-object v0
.end method

.method public static isCached(Lcom/perm/kate/api/Audio;)Z
    .locals 6

    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->fileFor(Lcom/perm/kate/api/Audio;)Ljava/io/File;

    move-result-object v0

    if-eqz v0, :nc_ret

    invoke-virtual {v0}, Ljava/io/File;->exists()Z

    move-result v1

    if-eqz v1, :nc_ret

    invoke-virtual {v0}, Ljava/io/File;->length()J

    move-result-wide v1

    const-wide/16 v3, 0x0

    cmp-long v5, v1, v3

    if-lez v5, :nc_ret

    const/4 v0, 0x1

    return v0

    :nc_ret
    const/4 v0, 0x0

    return v0
.end method

.method public static key(Lcom/perm/kate/api/Audio;)Ljava/lang/String;
    .locals 4

    if-eqz p0, :key_null

    new-instance v0, Ljava/lang/StringBuilder;

    invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V

    iget-wide v1, p0, Lcom/perm/kate/api/Audio;->owner_id:J

    invoke-virtual {v0, v1, v2}, Ljava/lang/StringBuilder;->append(J)Ljava/lang/StringBuilder;

    const/16 v1, 0x5f

    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(C)Ljava/lang/StringBuilder;

    iget-wide v1, p0, Lcom/perm/kate/api/Audio;->aid:J

    invoke-virtual {v0, v1, v2}, Ljava/lang/StringBuilder;->append(J)Ljava/lang/StringBuilder;

    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    return-object v0

    :key_null
    const/4 v0, 0x0

    return-object v0
.end method

.method public static limitBytes()J
    .locals 4

    sget-object v0, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    invoke-static {v0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;

    move-result-object v0

    const-string v1, "key_audio_cache_limit_mb"

    const/16 v2, 0x100

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getInt(Ljava/lang/String;I)I

    move-result v0

    if-nez v0, :f53_lb_ok

    const/16 v0, 0x100

    :f53_lb_ok
    int-to-long v0, v0

    const-wide/32 v2, 0x100000

    mul-long/2addr v0, v2

    return-wide v0
.end method

.method public static refresh(Ljava/lang/String;I)V
    .locals 3

    new-instance v0, Lcom/perm/kate/audio_cache/AudioCacheManager$2;

    invoke-direct {v0, p0, p1}, Lcom/perm/kate/audio_cache/AudioCacheManager$2;-><init>(Ljava/lang/String;I)V

    sget-object v1, Lcom/perm/kate/audio_cache/AudioCacheManager;->HANDLER:Landroid/os/Handler;

    invoke-virtual {v1, v0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z

    return-void
.end method

.method public static remove(Lcom/perm/kate/api/Audio;)V
    .locals 6

    if-eqz p0, :rm_ret

    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->key(Lcom/perm/kate/api/Audio;)Ljava/lang/String;

    move-result-object v0

    if-eqz v0, :rm_ret

    sget-object v1, Lcom/perm/kate/audio_cache/AudioCacheManager;->PENDING:Ljava/util/Set;

    invoke-interface {v1, v0}, Ljava/util/Set;->remove(Ljava/lang/Object;)Z

    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->fileFor(Lcom/perm/kate/api/Audio;)Ljava/io/File;

    move-result-object v1

    if-eqz v1, :rm_db

    invoke-virtual {v1}, Ljava/io/File;->delete()Z

    :rm_db
    sget-object v1, Lcom/perm/kate/KApplication;->db:Lcom/perm/kate/db/DataHelper;

    if-eqz v1, :rm_ref

    iget-wide v2, p0, Lcom/perm/kate/api/Audio;->aid:J

    iget-wide v4, p0, Lcom/perm/kate/api/Audio;->owner_id:J

    invoke-virtual {v1, v2, v3, v4, v5}, Lcom/perm/kate/db/DataHelper;->removeAudioCache(JJ)V

    :rm_ref
    const/4 v1, -0x2

    invoke-static {v0, v1}, Lcom/perm/kate/audio_cache/AudioCacheManager;->refresh(Ljava/lang/String;I)V

    :rm_ret
    return-void
.end method

.method public static retry(Lcom/perm/kate/api/Audio;)V
    .locals 1

    if-eqz p0, :ret_ret

    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->fileFor(Lcom/perm/kate/api/Audio;)Ljava/io/File;

    move-result-object v0

    if-eqz v0, :ret_add

    invoke-virtual {v0}, Ljava/io/File;->delete()Z

    :ret_add
    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->fetch(Lcom/perm/kate/api/Audio;)V

    :ret_ret
    return-void
.end method

.method public static sizeOf(Ljava/io/File;)J
    .locals 8

    const-wide/16 v0, 0x0

    if-eqz p0, :sz_ret

    invoke-virtual {p0}, Ljava/io/File;->isFile()Z

    move-result v2

    if-eqz v2, :sz_dir

    invoke-virtual {p0}, Ljava/io/File;->length()J

    move-result-wide v0

    return-wide v0

    :sz_dir
    invoke-virtual {p0}, Ljava/io/File;->listFiles()[Ljava/io/File;

    move-result-object v2

    if-eqz v2, :sz_ret

    array-length v3, v2

    const/4 v4, 0x0

    :sz_loop
    if-ge v4, v3, :sz_ret

    aget-object v5, v2, v4

    invoke-static {v5}, Lcom/perm/kate/audio_cache/AudioCacheManager;->sizeOf(Ljava/io/File;)J

    move-result-wide v6

    add-long/2addr v0, v6

    add-int/lit8 v4, v4, 0x1

    goto :sz_loop

    :sz_ret
    return-wide v0
.end method

.method public static status(Lcom/perm/kate/api/Audio;)I
    .locals 5

    if-eqz p0, :st_none

    sget-object v0, Lcom/perm/kate/KApplication;->db:Lcom/perm/kate/db/DataHelper;

    if-eqz v0, :st_none

    iget-wide v1, p0, Lcom/perm/kate/api/Audio;->aid:J

    iget-wide v3, p0, Lcom/perm/kate/api/Audio;->owner_id:J

    invoke-virtual {v0, v1, v2, v3, v4}, Lcom/perm/kate/db/DataHelper;->audioCacheStatus(JJ)I

    move-result v0

    const/4 v1, 0x3

    if-eq v0, v1, :st_check3

    const/4 v1, 0x2

    if-eq v0, v1, :st_check2

    return v0

    :st_check3
    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->isCached(Lcom/perm/kate/api/Audio;)Z

    move-result v1

    if-eqz v1, :st_ret3

    return v0

    :st_ret3
    const/4 v0, -0x1

    return v0

    :st_check2
    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->isCached(Lcom/perm/kate/api/Audio;)Z

    move-result v1

    if-nez v1, :st_cached

    return v0

    :st_cached
    const/4 v0, 0x3

    return v0

    :st_none
    const/4 v0, -0x1

    return v0
.end method

.method public static usedBytes()J
    .locals 2

    invoke-static {}, Lcom/perm/kate/audio_cache/AudioCacheManager;->cacheDir()Ljava/io/File;

    move-result-object v0

    invoke-static {v0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->sizeOf(Ljava/io/File;)J

    move-result-wide v0

    return-wide v0
.end method
'''

DOWNLOAD = '''.class final Lcom/perm/kate/audio_cache/AudioCacheManager$1;
.super Ljava/lang/Object;
.source "AudioCacheManager.java"

# interfaces
.implements Ljava/lang/Runnable;


# instance fields
.field private state:I

.field private final val$audio:Lcom/perm/kate/api/Audio;


# direct methods
.method public constructor <init>(Lcom/perm/kate/api/Audio;)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$1;->val$audio:Lcom/perm/kate/api/Audio;

    return-void
.end method


# virtual methods
.method public run()V
    .locals 14

    iget v0, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$1;->state:I

    if-eqz v0, :run_download

    iget-object v0, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$1;->val$audio:Lcom/perm/kate/api/Audio;

    invoke-static {v0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->key(Lcom/perm/kate/api/Audio;)Ljava/lang/String;

    move-result-object v1

    sget-object v2, Lcom/perm/kate/audio_cache/AudioCacheManager;->PENDING:Ljava/util/Set;

    invoke-interface {v2, v1}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z

    move-result v3

    invoke-interface {v2, v1}, Ljava/util/Set;->remove(Ljava/lang/Object;)Z

    const/4 v2, 0x0

    sput-object v2, Lcom/perm/kate/audio_cache/AudioCacheService;->currentDownloadId:Ljava/lang/Long;

    sput-boolean v2, Lcom/perm/kate/audio_cache/AudioCacheService;->is_working:Z

    if-eqz v3, :run_cancel

    iget v2, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$1;->state:I

    const/4 v3, 0x1

    const/4 v7, 0x3

    if-eq v2, v3, :run_status

    const/4 v7, 0x2

    :run_status
    sget-object v2, Lcom/perm/kate/KApplication;->db:Lcom/perm/kate/db/DataHelper;

    if-eqz v2, :run_refresh

    iget-wide v3, v0, Lcom/perm/kate/api/Audio;->aid:J

    iget-wide v5, v0, Lcom/perm/kate/api/Audio;->owner_id:J

    invoke-virtual/range {v2 .. v7}, Lcom/perm/kate/db/DataHelper;->setAudioCacheStatus(JJI)V

    :run_refresh
    invoke-static {v1, v7}, Lcom/perm/kate/audio_cache/AudioCacheManager;->refresh(Ljava/lang/String;I)V

    iget v0, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$1;->state:I

    const/4 v1, 0x1

    if-ne v0, v1, :run_ret

    invoke-static {}, Lcom/perm/kate/audio_cache/AudioCacheManager;->enforceLimit()V

    :run_ret
    return-void

    :run_cancel
    invoke-static {v0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->fileFor(Lcom/perm/kate/api/Audio;)Ljava/io/File;

    move-result-object v2

    if-eqz v2, :run_cancel_db

    invoke-virtual {v2}, Ljava/io/File;->delete()Z

    :run_cancel_db
    sget-object v2, Lcom/perm/kate/KApplication;->db:Lcom/perm/kate/db/DataHelper;

    if-eqz v2, :run_cancel_ref

    iget-wide v3, v0, Lcom/perm/kate/api/Audio;->aid:J

    iget-wide v5, v0, Lcom/perm/kate/api/Audio;->owner_id:J

    invoke-virtual {v2, v3, v4, v5, v6}, Lcom/perm/kate/db/DataHelper;->removeAudioCache(JJ)V

    :run_cancel_ref
    const/4 v0, -0x2

    invoke-static {v1, v0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->refresh(Ljava/lang/String;I)V

    return-void

    :run_download
    iget-object v0, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$1;->val$audio:Lcom/perm/kate/api/Audio;

    invoke-static {v0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->fileFor(Lcom/perm/kate/api/Audio;)Ljava/io/File;

    move-result-object v1

    const/4 v2, 0x2

    if-eqz v1, :run_dl_end

    invoke-virtual {v1}, Ljava/io/File;->getParentFile()Ljava/io/File;

    move-result-object v3

    if-eqz v3, :run_dl_a1

    invoke-virtual {v3}, Ljava/io/File;->mkdirs()Z

    :run_dl_a1
    new-instance v3, Ljava/io/File;

    new-instance v4, Ljava/lang/StringBuilder;

    invoke-direct {v4}, Ljava/lang/StringBuilder;-><init>()V

    invoke-virtual {v1}, Ljava/io/File;->getAbsolutePath()Ljava/lang/String;

    move-result-object v5

    invoke-virtual {v4, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v5, ".part"

    invoke-virtual {v4, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v4}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v4

    invoke-direct {v3, v4}, Ljava/io/File;-><init>(Ljava/lang/String;)V

    const/4 v4, 0x0

    const/4 v5, 0x0

    const/4 v6, 0x0

    const/4 v11, 0x0

    :try_start_0
    new-instance v7, Ljava/net/URL;

    iget-object v8, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$1;->val$audio:Lcom/perm/kate/api/Audio;

    iget-object v8, v8, Lcom/perm/kate/api/Audio;->url:Ljava/lang/String;

    invoke-direct {v7, v8}, Ljava/net/URL;-><init>(Ljava/lang/String;)V

    invoke-static {v7}, Lcom/perm/utils/ProxyManager;->getConnection(Ljava/net/URL;)Ljava/net/HttpURLConnection;

    move-result-object v5

    const/16 v7, 0x7530

    invoke-virtual {v5, v7}, Ljava/net/URLConnection;->setConnectTimeout(I)V

    invoke-virtual {v5, v7}, Ljava/net/URLConnection;->setReadTimeout(I)V

    const/4 v7, 0x0

    invoke-virtual {v5, v7}, Ljava/net/URLConnection;->setUseCaches(Z)V

    const-string v7, "Range"

    const-string v8, "bytes=0-"

    invoke-virtual {v5, v7, v8}, Ljava/net/URLConnection;->setRequestProperty(Ljava/lang/String;Ljava/lang/String;)V

    invoke-virtual {v5}, Ljava/net/URLConnection;->connect()V

    invoke-virtual {v5}, Ljava/net/HttpURLConnection;->getResponseCode()I

    move-result v7

    const/16 v8, 0xc8

    if-eq v7, v8, :run_dl_status

    const/16 v8, 0xce

    if-eq v7, v8, :run_dl_status

    :run_dl_bad
    new-instance v7, Ljava/io/IOException;

    const-string v8, "unexpected http status"

    invoke-direct {v7, v8}, Ljava/io/IOException;-><init>(Ljava/lang/String;)V

    throw v7

    :run_dl_status
    invoke-virtual {v5}, Ljava/net/URLConnection;->getContentLength()I

    move-result v7

    const/4 v8, 0x0

    invoke-static {v7, v8}, Ljava/lang/Math;->max(II)I

    move-result v7

    sput v7, Lcom/perm/kate/audio_cache/AudioCacheService;->currentLength:I

    const/4 v7, 0x0

    sput v7, Lcom/perm/kate/audio_cache/AudioCacheService;->currentProgress:I

    iget-object v7, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$1;->val$audio:Lcom/perm/kate/api/Audio;

    iget-wide v7, v7, Lcom/perm/kate/api/Audio;->aid:J

    invoke-static {v7, v8}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;

    move-result-object v7

    sput-object v7, Lcom/perm/kate/audio_cache/AudioCacheService;->currentDownloadId:Ljava/lang/Long;

    const/4 v7, 0x1

    sput-boolean v7, Lcom/perm/kate/audio_cache/AudioCacheService;->is_working:Z

    const/4 v7, 0x0

    const/4 v8, -0x1

    invoke-static {v7, v8}, Lcom/perm/kate/audio_cache/AudioCacheManager;->refresh(Ljava/lang/String;I)V

    new-instance v7, Ljava/io/FileOutputStream;

    invoke-direct {v7, v3}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V

    move-object v4, v7

    new-instance v7, Ljava/io/BufferedInputStream;

    invoke-virtual {v5}, Ljava/net/URLConnection;->getInputStream()Ljava/io/InputStream;

    move-result-object v8

    const/16 v9, 0x2000

    invoke-direct {v7, v8, v9}, Ljava/io/BufferedInputStream;-><init>(Ljava/io/InputStream;I)V

    move-object v6, v7

    new-array v8, v9, [B

    const/4 v10, 0x0

    :goto_0
    invoke-virtual {v6, v8, v10, v9}, Ljava/io/InputStream;->read([BII)I

    move-result v12

    const/4 v13, -0x1

    if-eq v12, v13, :run_dl_copy

    invoke-virtual {v4, v8, v10, v12}, Ljava/io/FileOutputStream;->write([BII)V

    add-int/2addr v11, v12

    sget v13, Lcom/perm/kate/audio_cache/AudioCacheService;->currentProgress:I

    add-int/2addr v13, v12

    sput v13, Lcom/perm/kate/audio_cache/AudioCacheService;->currentProgress:I

    goto :goto_0

    :run_dl_copy
    invoke-virtual {v4}, Ljava/io/OutputStream;->flush()V

    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_0

    invoke-static {v4}, Lcom/perm/kate/audio_cache/AudioCacheManager;->close(Ljava/io/Closeable;)V

    invoke-static {v6}, Lcom/perm/kate/audio_cache/AudioCacheManager;->close(Ljava/io/Closeable;)V

    invoke-static {v5}, Lcom/perm/kate/audio_cache/AudioCacheManager;->closeConn(Ljava/net/HttpURLConnection;)V

    sget v13, Lcom/perm/kate/audio_cache/AudioCacheService;->currentLength:I

    if-eqz v13, :run_dl_size_ok

    if-ne v11, v13, :run_dl_fail

    :run_dl_size_ok
    const/4 v13, 0x0

    if-eq v11, v13, :run_dl_fail

    invoke-virtual {v3, v1}, Ljava/io/File;->renameTo(Ljava/io/File;)Z

    move-result v4

    if-eqz v4, :run_dl_fail

    const/4 v2, 0x1

    goto :run_dl_end

    :run_dl_fail
    invoke-virtual {v3}, Ljava/io/File;->delete()Z

    goto :run_dl_end

    :catchall_0
    move-exception v7

    invoke-static {v4}, Lcom/perm/kate/audio_cache/AudioCacheManager;->close(Ljava/io/Closeable;)V

    invoke-static {v6}, Lcom/perm/kate/audio_cache/AudioCacheManager;->close(Ljava/io/Closeable;)V

    invoke-static {v5}, Lcom/perm/kate/audio_cache/AudioCacheManager;->closeConn(Ljava/net/HttpURLConnection;)V

    invoke-virtual {v3}, Ljava/io/File;->delete()Z

    const/4 v2, 0x2

    :run_dl_end
    iput v2, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$1;->state:I

    sget-object v0, Lcom/perm/kate/audio_cache/AudioCacheManager;->HANDLER:Landroid/os/Handler;

    invoke-virtual {v0, p0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z

    return-void
.end method
'''

FETCH = '''.class final Lcom/perm/kate/audio_cache/AudioCacheManager$4;
.super Ljava/lang/Object;
.source "AudioCacheManager.java"

# interfaces
.implements Ljava/lang/Runnable;


# instance fields
.field private final val$audio:Lcom/perm/kate/api/Audio;


# direct methods
.method public constructor <init>(Lcom/perm/kate/api/Audio;)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$4;->val$audio:Lcom/perm/kate/api/Audio;

    return-void
.end method


# virtual methods
.method public run()V
    .locals 5

    iget-object v0, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$4;->val$audio:Lcom/perm/kate/api/Audio;

    new-instance v1, Ljava/lang/StringBuilder;

    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V

    iget-wide v2, v0, Lcom/perm/kate/api/Audio;->owner_id:J

    invoke-virtual {v1, v2, v3}, Ljava/lang/StringBuilder;->append(J)Ljava/lang/StringBuilder;

    const/16 v2, 0x5f

    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(C)Ljava/lang/StringBuilder;

    iget-wide v2, v0, Lcom/perm/kate/api/Audio;->aid:J

    invoke-virtual {v1, v2, v3}, Ljava/lang/StringBuilder;->append(J)Ljava/lang/StringBuilder;

    invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v1

    :try_start_0
    sget-object v2, Lcom/perm/kate/KApplication;->session:Lcom/perm/kate/session/Session;

    if-eqz v2, :fetch_fail

    iget-object v2, v2, Lcom/perm/kate/session/Session;->api:Lcom/perm/kate/api/Api;

    if-eqz v2, :fetch_fail

    const/4 v3, 0x0

    const/4 v4, 0x0

    invoke-virtual {v2, v1, v3, v4}, Lcom/perm/kate/api/Api;->getAudioById(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/util/ArrayList;

    move-result-object v1
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_0

    if-eqz v1, :fetch_fail

    invoke-virtual {v1}, Ljava/util/ArrayList;->isEmpty()Z

    move-result v2

    if-nez v2, :fetch_fail

    const/4 v2, 0x0

    invoke-virtual {v1, v2}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;

    move-result-object v1

    check-cast v1, Lcom/perm/kate/api/Audio;

    if-eqz v1, :fetch_fail

    invoke-static {v1}, Lcom/perm/kate/audio_cache/AudioCacheManager;->add(Lcom/perm/kate/api/Audio;)V

    return-void

    :catchall_0
    move-exception v1

    :fetch_fail
    invoke-static {v0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->fail(Lcom/perm/kate/api/Audio;)V

    return-void
.end method
'''

REFRESH = '''.class final Lcom/perm/kate/audio_cache/AudioCacheManager$2;
.super Ljava/lang/Object;
.source "AudioCacheManager.java"

# interfaces
.implements Ljava/lang/Runnable;


# instance fields
.field private final val$key:Ljava/lang/String;

.field private final val$status:I


# direct methods
.method public constructor <init>(Ljava/lang/String;I)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$2;->val$key:Ljava/lang/String;

    iput p2, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$2;->val$status:I

    return-void
.end method


# virtual methods
.method public run()V
    .locals 4

    sget-object v0, Lcom/perm/kate/audio_cache/AudioCacheManager;->adapter:Lcom/perm/kate/AudioListAdapter;

    if-eqz v0, :refresh_notify

    iget v1, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$2;->val$status:I

    const/4 v2, -0x1

    if-ne v1, v2, :refresh_notify

    const/4 v2, -0x2

    if-ne v1, v2, :refresh_remove

    iget-object v2, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$2;->val$key:Ljava/lang/String;

    if-eqz v2, :refresh_notify

    iget-object v3, v0, Lcom/perm/kate/AudioListAdapter;->downloadStates:Ljava/util/HashMap;

    invoke-static {v1}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v1

    invoke-virtual {v3, v2, v1}, Ljava/util/HashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;

    goto :refresh_notify

    :refresh_remove
    iget-object v2, p0, Lcom/perm/kate/audio_cache/AudioCacheManager$2;->val$key:Ljava/lang/String;

    if-eqz v2, :refresh_notify

    iget-object v3, v0, Lcom/perm/kate/AudioListAdapter;->downloadStates:Ljava/util/HashMap;

    invoke-virtual {v3, v2}, Ljava/util/HashMap;->remove(Ljava/lang/Object;)Ljava/lang/Object;

    :refresh_notify
    if-eqz v0, :refresh_ret

    invoke-virtual {v0}, Landroid/widget/BaseAdapter;->notifyDataSetChanged()V

    sget-boolean v0, Lcom/perm/kate/audio_cache/AudioCacheService;->is_working:Z

    if-eqz v0, :refresh_ret

    sget-object v0, Lcom/perm/kate/audio_cache/AudioCacheManager;->HANDLER:Landroid/os/Handler;

    const-wide/16 v1, 0x1f4

    invoke-virtual {v0, p0, v1, v2}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z

    :refresh_ret
    return-void
.end method
'''

PREF = '''.class public Lcom/perm/kate/CacheLimitPreference;
.super Landroid/preference/Preference;
.source "CacheLimitPreference.java"


# direct methods
.method public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;)V
    .locals 0

    invoke-direct {p0, p1, p2}, Landroid/preference/Preference;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;)V

    return-void
.end method

.method public applyLimit(I)V
    .locals 0

    if-nez p1, :f53_al_ok

    const/4 p1, 0x1

    :f53_al_ok
    mul-int/lit16 p1, p1, 0x100

    invoke-virtual {p0, p1}, Landroid/preference/Preference;->persistInt(I)Z

    invoke-virtual {p0}, Lcom/perm/kate/CacheLimitPreference;->updateSummary()V

    invoke-static {}, Lcom/perm/kate/audio_cache/AudioCacheManager;->enforceLimit()V

    return-void
.end method

.method public static labelFor(I)Ljava/lang/String;
    .locals 4

    if-eqz p0, :lf_none

    mul-int/lit16 p0, p0, 0x100

    const/16 v0, 0x400

    rem-int v1, p0, v0

    if-eqz v1, :lf_gb

    new-instance v1, Ljava/lang/StringBuilder;

    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V

    invoke-virtual {v1, p0}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    const-string v2, " МБ"

    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    return-object v0

    :lf_gb
    div-int v1, p0, v0

    new-instance v2, Ljava/lang/StringBuilder;

    invoke-direct {v2}, Ljava/lang/StringBuilder;-><init>()V

    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    const-string v3, " ГБ ("

    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v2, p0}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    const-string v3, " МБ)"

    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    return-object v0

    :lf_none
    const-string v0, "Без лимита"

    return-object v0
.end method

.method protected onClick()V
    .locals 8

    invoke-virtual {p0}, Landroid/preference/Preference;->getContext()Landroid/content/Context;

    move-result-object v0

    const/16 v1, 0x100

    invoke-virtual {p0, v1}, Landroid/preference/Preference;->getPersistedInt(I)I

    move-result v1

    div-int/lit16 v1, v1, 0x100

    if-nez v1, :f53_cl_idx_ok

    const/4 v1, 0x1

    :f53_cl_idx_ok
    add-int/lit8 v1, v1, -0x1

    new-instance v2, Landroid/widget/LinearLayout;

    invoke-direct {v2, v0}, Landroid/widget/LinearLayout;-><init>(Landroid/content/Context;)V

    const/4 v3, 0x1

    invoke-virtual {v2, v3}, Landroid/widget/LinearLayout;->setOrientation(I)V

    invoke-virtual {v0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;

    move-result-object v3

    invoke-virtual {v3}, Landroid/content/res/Resources;->getDisplayMetrics()Landroid/util/DisplayMetrics;

    move-result-object v3

    iget v3, v3, Landroid/util/DisplayMetrics;->density:F

    const/high16 v4, 0x41800000    # 16.0f

    mul-float/2addr v3, v4

    float-to-int v3, v3

    invoke-virtual {v2, v3, v3, v3, v3}, Landroid/widget/LinearLayout;->setPadding(IIII)V

    new-instance v4, Landroid/widget/TextView;

    invoke-direct {v4, v0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V

    add-int/lit8 v5, v1, 0x1

    invoke-static {v5}, Lcom/perm/kate/CacheLimitPreference;->labelFor(I)Ljava/lang/String;

    move-result-object v5

    invoke-virtual {v4, v5}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V

    invoke-virtual {v2, v4}, Landroid/widget/LinearLayout;->addView(Landroid/view/View;)V

    new-instance v5, Landroid/widget/SeekBar;

    invoke-direct {v5, v0}, Landroid/widget/SeekBar;-><init>(Landroid/content/Context;)V

    const/16 v6, 0x1f

    invoke-virtual {v5, v6}, Landroid/widget/SeekBar;->setMax(I)V

    invoke-virtual {v5, v1}, Landroid/widget/SeekBar;->setProgress(I)V

    new-instance v6, Lcom/perm/kate/CacheLimitPreference$1;

    invoke-direct {v6, v4}, Lcom/perm/kate/CacheLimitPreference$1;-><init>(Landroid/widget/TextView;)V

    invoke-virtual {v5, v6}, Landroid/widget/SeekBar;->setOnSeekBarChangeListener(Landroid/widget/SeekBar$OnSeekBarChangeListener;)V

    invoke-virtual {v2, v5}, Landroid/widget/LinearLayout;->addView(Landroid/view/View;)V

    new-instance v4, Landroid/app/AlertDialog$Builder;

    invoke-direct {v4, v0}, Landroid/app/AlertDialog$Builder;-><init>(Landroid/content/Context;)V

    const-string v0, "Лимит кэша аудио"

    invoke-virtual {v4, v0}, Landroid/app/AlertDialog$Builder;->setTitle(Ljava/lang/CharSequence;)Landroid/app/AlertDialog$Builder;

    move-result-object v4

    invoke-virtual {v4, v2}, Landroid/app/AlertDialog$Builder;->setView(Landroid/view/View;)Landroid/app/AlertDialog$Builder;

    move-result-object v4

    new-instance v0, Lcom/perm/kate/CacheLimitPreference$2;

    invoke-direct {v0, p0, v5}, Lcom/perm/kate/CacheLimitPreference$2;-><init>(Lcom/perm/kate/CacheLimitPreference;Landroid/widget/SeekBar;)V

    const-string v2, "ОК"

    invoke-virtual {v4, v2, v0}, Landroid/app/AlertDialog$Builder;->setPositiveButton(Ljava/lang/CharSequence;Landroid/content/DialogInterface$OnClickListener;)Landroid/app/AlertDialog$Builder;

    move-result-object v4

    const-string v0, "Отмена"

    const/4 v2, 0x0

    invoke-virtual {v4, v0, v2}, Landroid/app/AlertDialog$Builder;->setNegativeButton(Ljava/lang/CharSequence;Landroid/content/DialogInterface$OnClickListener;)Landroid/app/AlertDialog$Builder;

    move-result-object v0

    invoke-virtual {v0}, Landroid/app/AlertDialog$Builder;->show()Landroid/app/AlertDialog;

    return-void
.end method

.method public getSummary()Ljava/lang/CharSequence;
    .locals 6

    invoke-virtual {p0}, Landroid/preference/Preference;->getContext()Landroid/content/Context;

    move-result-object v0

    const/16 v1, 0x100

    invoke-virtual {p0, v1}, Landroid/preference/Preference;->getPersistedInt(I)I

    move-result v1

    div-int/lit16 v1, v1, 0x100

    if-nez v1, :f53_gs_idx_ok

    const/4 v1, 0x1

    :f53_gs_idx_ok
    invoke-static {v1}, Lcom/perm/kate/CacheLimitPreference;->labelFor(I)Ljava/lang/String;

    move-result-object v2

    invoke-static {}, Lcom/perm/kate/audio_cache/AudioCacheManager;->usedBytes()J

    move-result-wide v3

    invoke-static {v0, v3, v4}, Landroid/text/format/Formatter;->formatFileSize(Landroid/content/Context;J)Ljava/lang/String;

    move-result-object v3

    new-instance v4, Ljava/lang/StringBuilder;

    invoke-direct {v4}, Ljava/lang/StringBuilder;-><init>()V

    invoke-virtual {v4, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v2, " · занято "

    invoke-virtual {v4, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v4, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v4}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v2

    return-object v2
.end method

.method public updateSummary()V
    .locals 0

    invoke-virtual {p0}, Landroid/preference/Preference;->notifyChanged()V

    return-void
.end method
'''

PREF1 = '''.class final Lcom/perm/kate/CacheLimitPreference$1;
.super Ljava/lang/Object;
.source "CacheLimitPreference.java"

# interfaces
.implements Landroid/widget/SeekBar$OnSeekBarChangeListener;


# instance fields
.field private final val$label:Landroid/widget/TextView;


# direct methods
.method public constructor <init>(Landroid/widget/TextView;)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lcom/perm/kate/CacheLimitPreference$1;->val$label:Landroid/widget/TextView;

    return-void
.end method


# virtual methods
.method public onProgressChanged(Landroid/widget/SeekBar;IZ)V
    .locals 1

    iget-object v0, p0, Lcom/perm/kate/CacheLimitPreference$1;->val$label:Landroid/widget/TextView;

    add-int/lit8 p2, p2, 0x1

    invoke-static {p2}, Lcom/perm/kate/CacheLimitPreference;->labelFor(I)Ljava/lang/String;

    move-result-object p1

    invoke-virtual {v0, p1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V

    return-void
.end method

.method public onStartTrackingTouch(Landroid/widget/SeekBar;)V
    .locals 0

    return-void
.end method

.method public onStopTrackingTouch(Landroid/widget/SeekBar;)V
    .locals 0

    return-void
.end method
'''

PREF2 = '''.class final Lcom/perm/kate/CacheLimitPreference$2;
.super Ljava/lang/Object;
.source "CacheLimitPreference.java"

# interfaces
.implements Landroid/content/DialogInterface$OnClickListener;


# instance fields
.field private final val$bar:Landroid/widget/SeekBar;

.field private final val$pref:Lcom/perm/kate/CacheLimitPreference;


# direct methods
.method public constructor <init>(Lcom/perm/kate/CacheLimitPreference;Landroid/widget/SeekBar;)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lcom/perm/kate/CacheLimitPreference$2;->val$pref:Lcom/perm/kate/CacheLimitPreference;

    iput-object p2, p0, Lcom/perm/kate/CacheLimitPreference$2;->val$bar:Landroid/widget/SeekBar;

    return-void
.end method


# virtual methods
.method public onClick(Landroid/content/DialogInterface;I)V
    .locals 2

    iget-object p1, p0, Lcom/perm/kate/CacheLimitPreference$2;->val$bar:Landroid/widget/SeekBar;

    invoke-virtual {p1}, Landroid/widget/SeekBar;->getProgress()I

    move-result p1

    add-int/lit8 p1, p1, 0x1

    iget-object p2, p0, Lcom/perm/kate/CacheLimitPreference$2;->val$pref:Lcom/perm/kate/CacheLimitPreference;

    invoke-virtual {p2, p1}, Lcom/perm/kate/CacheLimitPreference;->applyLimit(I)V

    return-void
.end method
'''

DATAHELPER = '''
# f53_audio_cache: DataHelper
.method public audioCacheStatus(JJ)I
    .locals 6

    const/4 v0, -0x1

    iget-object v1, p0, Lcom/perm/kate/db/DataHelper;->mDbHelper:Lcom/perm/kate/db/DataHelper$OpenHelper;

    invoke-virtual {v1}, Landroid/database/sqlite/SQLiteOpenHelper;->getWritableDatabase()Landroid/database/sqlite/SQLiteDatabase;

    move-result-object v1

    const-string v2, "select status from audio_cache where audio_id=? and owner_id=? limit 1"

    const/4 v3, 0x2

    new-array v3, v3, [Ljava/lang/String;

    const/4 v4, 0x0

    invoke-static {p1, p2}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object v5

    aput-object v5, v3, v4

    const/4 v4, 0x1

    invoke-static {p3, p4}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object v5

    aput-object v5, v3, v4

    invoke-virtual {v1, v2, v3}, Landroid/database/sqlite/SQLiteDatabase;->rawQuery(Ljava/lang/String;[Ljava/lang/String;)Landroid/database/Cursor;

    move-result-object v1

    invoke-interface {v1}, Landroid/database/Cursor;->moveToFirst()Z

    move-result v2

    if-eqz v2, :acs_ret

    const/4 v2, 0x0

    invoke-interface {v1, v2}, Landroid/database/Cursor;->getInt(I)I

    move-result v0

    :acs_ret
    invoke-interface {v1}, Landroid/database/Cursor;->close()V

    return v0
.end method

.method public removeAudioCache(JJ)V
    .locals 6

    iget-object v0, p0, Lcom/perm/kate/db/DataHelper;->mDbHelper:Lcom/perm/kate/db/DataHelper$OpenHelper;

    invoke-virtual {v0}, Landroid/database/sqlite/SQLiteOpenHelper;->getWritableDatabase()Landroid/database/sqlite/SQLiteDatabase;

    move-result-object v0

    const/4 v1, 0x2

    new-array v2, v1, [Ljava/lang/Object;

    const/4 v1, 0x0

    invoke-static {p1, p2}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;

    move-result-object v3

    aput-object v3, v2, v1

    const/4 v1, 0x1

    invoke-static {p3, p4}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;

    move-result-object v3

    aput-object v3, v2, v1

    const-string v1, "delete from audio_cache where audio_id=? and owner_id=?"

    invoke-virtual {v0, v1, v2}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;[Ljava/lang/Object;)V

    return-void
.end method

.method public setAudioCacheStatus(JJI)V
    .locals 6

    iget-object v0, p0, Lcom/perm/kate/db/DataHelper;->mDbHelper:Lcom/perm/kate/db/DataHelper$OpenHelper;

    invoke-virtual {v0}, Landroid/database/sqlite/SQLiteOpenHelper;->getWritableDatabase()Landroid/database/sqlite/SQLiteDatabase;

    move-result-object v0

    const/4 v1, 0x2

    new-array v2, v1, [Ljava/lang/Object;

    const/4 v1, 0x0

    invoke-static {p1, p2}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;

    move-result-object v3

    aput-object v3, v2, v1

    const/4 v1, 0x1

    invoke-static {p3, p4}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;

    move-result-object v3

    aput-object v3, v2, v1

    const-string v1, "delete from audio_cache where audio_id=? and owner_id=?"

    invoke-virtual {v0, v1, v2}, Landroid/database/sqlite/SQLiteDatabase;->execSQL(Ljava/lang/String;[Ljava/lang/Object;)V

    new-instance v1, Landroid/content/ContentValues;

    invoke-direct {v1}, Landroid/content/ContentValues;-><init>()V

    const-string v2, "audio_id"

    invoke-static {p1, p2}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;

    move-result-object v3

    invoke-virtual {v1, v2, v3}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/Long;)V

    const-string v2, "owner_id"

    invoke-static {p3, p4}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;

    move-result-object v3

    invoke-virtual {v1, v2, v3}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/Long;)V

    const-string v2, "status"

    invoke-static {p5}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v3

    invoke-virtual {v1, v2, v3}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/Integer;)V

    const-string v2, "audio_cache"

    const/4 v3, 0x0

    invoke-virtual {v0, v2, v3, v1}, Landroid/database/sqlite/SQLiteDatabase;->insert(Ljava/lang/String;Ljava/lang/String;Landroid/content/ContentValues;)J

    return-void
.end method
'''


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, s):
    with open(path, "w", encoding="utf-8") as f:
        f.write(s)


def ensure_class(path, body):
    if os.path.exists(path):
        if read(path) == body:
            print("f53 %s: уже существует" % os.path.basename(path))
            return
        write(path, body)
        print("f53 %s: обновлён" % os.path.basename(path))
        return
    write(path, body)
    print("f53 %s: создан" % os.path.basename(path))


# --- 1) новые классы ----------------------------------------------------------
ensure_class(ACACHE + "AudioCacheManager.smali", MANAGER)
ensure_class(ACACHE + "AudioCacheManager$1.smali", DOWNLOAD)
ensure_class(ACACHE + "AudioCacheManager$4.smali", FETCH)
ensure_class(ACACHE + "AudioCacheManager$2.smali", REFRESH)
ensure_class(BASE + "CacheLimitPreference.smali", PREF)
ensure_class(BASE + "CacheLimitPreference$1.smali", PREF1)
ensure_class(BASE + "CacheLimitPreference$2.smali", PREF2)

# --- 2) DataHelper: методы audio_cache ----------------------------------------
p = BASE + "db/DataHelper.smali"
s = read(p)
if MARK + ": DataHelper" in s:
    print("f53 DataHelper: методы уже добавлены")
else:
    assert s.rstrip().endswith(".end method"), "f53: DataHelper не заканчивается .end method"
    write(p, s.rstrip("\n") + "\n" + DATAHELPER)
    print("f53 DataHelper: методы добавлены")

# --- 3) меню аудио: ручное скачивание отключено --------------------------------
# Пункты 0x14/0x15/0x16 и их обработка не добавляются: автокэш при
# прослушивании остаётся, ручное «Скачать в кэш» / «Продолжить загрузку» — нет.

# --- 5) автокэш при прослушивании ---------------------------------------------
p = BASE + "AudioClickHelper.smali"
s = read(p)
if MARK + ": auto" in s:
    print("f53 AudioClickHelper: автокэш уже добавлен")
else:
    anchor = """    .line 495
    :cond_1
    sput-object p0, Lcom/perm/kate/PlaybackService;->episode:Lcom/perm/kate/api/Audio;"""
    assert s.count(anchor) == 1, "f53: якорь PlayAudio не найден/не уникален"
    block = """    .line 495
    :cond_1
    # f53_audio_cache: auto
    invoke-static {p0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->autoCache(Lcom/perm/kate/api/Audio;)V

    sput-object p0, Lcom/perm/kate/PlaybackService;->episode:Lcom/perm/kate/api/Audio;"""
    s = s.replace(anchor, block, 1)
    write(p, s)
    print("f53 AudioClickHelper: автокэш в PlayAudio добавлен")

# --- 6) локальный файл в getAudioUri ------------------------------------------
p = BASE + "PlaybackService.smali"
s = read(p)
if MARK + ": uri" in s:
    print("f53 PlaybackService: локальный файл уже добавлен")
else:
    anchor = """.method public final getAudioUri(Lcom/perm/kate/api/Audio;)Ljava/lang/String;
    .locals 0

    if-eqz p1, :cond_0

    .line 658
    iget-object p1, p1, Lcom/perm/kate/api/Audio;->url:Ljava/lang/String;"""
    assert s.count(anchor) == 1, "f53: якорь getAudioUri не найден/не уникален"
    block = """.method public final getAudioUri(Lcom/perm/kate/api/Audio;)Ljava/lang/String;
    .locals 2

    if-eqz p1, :cond_0

    # f53_audio_cache: uri
    invoke-static {p1}, Lcom/perm/kate/audio_cache/AudioCacheManager;->cachedPath(Lcom/perm/kate/api/Audio;)Ljava/lang/String;

    move-result-object v0

    if-eqz v0, :f53_uri_remote

    return-object v0

    :f53_uri_remote
    # f53_audio_cache: auto (здесь url уже получен от API)
    invoke-static {p1}, Lcom/perm/kate/audio_cache/AudioCacheManager;->autoCache(Lcom/perm/kate/api/Audio;)V

    .line 658
    iget-object p1, p1, Lcom/perm/kate/api/Audio;->url:Ljava/lang/String;"""
    s = s.replace(anchor, block, 1)
    write(p, s)
    print("f53 PlaybackService: локальный файл в getAudioUri добавлен")

# --- 7) привязка адаптера в AudioFragment -------------------------------------
p = BASE + "AudioFragment.smali"
s = read(p)
if MARK + ": attach" in s:
    print("f53 AudioFragment: адаптер уже привязан")
else:
    anchor = """.method private displayData()V
    .locals 7

    .line 266"""
    assert s.count(anchor) == 1, "f53: якорь displayData не найден/не уникален"
    block = """.method private displayData()V
    .locals 7

    # f53_audio_cache: attach
    iget-object v0, p0, Lcom/perm/kate/AudioFragment;->adapter:Lcom/perm/kate/AudioListAdapter;

    if-eqz v0, :f53_attach_done

    const/4 v1, 0x1

    iput-boolean v1, v0, Lcom/perm/kate/AudioListAdapter;->displayDownloadStates:Z

    invoke-static {v0}, Lcom/perm/kate/audio_cache/AudioCacheManager;->attach(Lcom/perm/kate/AudioListAdapter;)V

    :f53_attach_done
    .line 266"""
    s = s.replace(anchor, block, 1)
    write(p, s)
    print("f53 AudioFragment: адаптер привязан")

# --- 8) привязка адаптера в PlayerActivity ------------------------------------
p = BASE + "PlayerActivity.smali"
s = read(p)
if MARK + ": attach" in s:
    print("f53 PlayerActivity: адаптер уже привязан")
else:
    anchor = """    iput-object v2, v1, Lcom/perm/kate/AudioListAdapter;->downloadStates:Ljava/util/HashMap;

    .line 153"""
    assert s.count(anchor) == 1, "f53: якорь displayListData не найден/не уникален"
    block = """    iput-object v2, v1, Lcom/perm/kate/AudioListAdapter;->downloadStates:Ljava/util/HashMap;

    # f53_audio_cache: attach
    const/4 v3, 0x1

    iput-boolean v3, v1, Lcom/perm/kate/AudioListAdapter;->displayDownloadStates:Z

    invoke-static {v1}, Lcom/perm/kate/audio_cache/AudioCacheManager;->attach(Lcom/perm/kate/AudioListAdapter;)V

    .line 153"""
    s = s.replace(anchor, block, 1)
    write(p, s)
    print("f53 PlayerActivity: адаптер привязан")

# --- 9) пункты настроек -------------------------------------------------------
for rel in ("res/xml/preferences.xml", "res/xml-v22/preferences.xml"):
    p = "decode/" + rel
    s = read(p)
    if "key_audio_cache_limit_mb" in s:
        print("f53 %s: настройки уже добавлены" % rel)
        continue
    anchor = """        <PreferenceScreen android:title="@string/audio_cache_dir_title" android:key="audio_cache_dir_virtual" android:summary="@string/audio_cache_dir_summary" />"""
    assert s.count(anchor) == 1, "f53: якорь audio_cache_dir_virtual не найден в " + rel
    block = anchor + """
        <com.perm.kate.CacheLimitPreference android:title="Лимит кэша аудио" android:key="key_audio_cache_limit_mb" />
        <CheckBoxPreference android:title="Кэшировать прослушиваемое аудио" android:key="key_audio_cache_auto" android:defaultValue="true" />"""
    s = s.replace(anchor, block, 1)
    write(p, s)
    print("f53 %s: настройки добавлены" % rel)
PYEOF
