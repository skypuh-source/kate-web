#!/bin/sh
# f57_flood_backoff.sh — экспоненциальная пауза при VK error 9 (Flood control).
#
# Проблема: LongPoll при ошибке получения сервера повторяет запрос каждые
# 2 минуты (LongPoll$RequestServerThread$1.error, KException → 0x1d4c0).
# Если VK считает окно flood от последнего запроса, такие повторы не дают
# ему истечь: приложение может держать аккаунт под error 9 часами.
#
# Решение: при KException с error_code == 9 пауза растёт 10 → 30 → 60 минут
# (счётчик сбрасывается при успешном ответе сервера). Для остальных ошибок
# поведение прежнее: 2 минуты для KException, 1 минута для сетевых.
#
# Откат: удалить KateFloodBackoff.smali и вернуть блок в
# LongPoll$RequestServerThread$1.error / ready (маркер # f57_flood_backoff).
#
# Идемпотентен: повторный запуск ничего не дублирует.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
import os

BASE = "decode/smali/com/perm/kate/"
BACKOFF = BASE + "KateFloodBackoff.smali"
CALLBACK = BASE + "LongPoll$RequestServerThread$1.smali"
MARK = "# f57_flood_backoff"

BACKOFF_SMALI = '''.class public final Lcom/perm/kate/KateFloodBackoff;
.super Ljava/lang/Object;
.source "KateFloodBackoff.java"


# static fields
.field private static failCount:I


# direct methods
.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method


# virtual methods
.method public static next()J
    .locals 2

    # f57_flood_backoff: 10 -> 30 -> 60 минут
    sget v0, Lcom/perm/kate/KateFloodBackoff;->failCount:I

    add-int/lit8 v0, v0, 0x1

    sput v0, Lcom/perm/kate/KateFloodBackoff;->failCount:I

    const/4 v1, 0x1

    if-gt v0, v1, :cond_0

    const-wide/32 v0, 0x927c0

    return-wide v0

    :cond_0
    const/4 v1, 0x2

    if-ne v0, v1, :cond_1

    const-wide/32 v0, 0x1b7740

    return-wide v0

    :cond_1
    const-wide/32 v0, 0x36ee80

    return-wide v0
.end method

.method public static reset()V
    .locals 1

    # f57_flood_backoff: успешный ответ сервера
    const/4 v0, 0x0

    sput v0, Lcom/perm/kate/KateFloodBackoff;->failCount:I

    return-void
.end method
'''

OLD_ERROR = '''    .line 219
    instance-of p1, p1, Lcom/perm/kate/api/KException;

    if-eqz p1, :cond_1

    const-wide/32 v0, 0x1d4c0

    goto :goto_0

    :cond_1
    const-wide/32 v0, 0xea60

    .line 220
    :goto_0
'''

NEW_ERROR = '''    .line 219
    # f57_flood_backoff: error 9 — пауза 10/30/60 минут, чтобы окно flood истекало
    instance-of v1, p1, Lcom/perm/kate/api/KException;

    if-eqz v1, :cond_1

    check-cast p1, Lcom/perm/kate/api/KException;

    iget v2, p1, Lcom/perm/kate/api/KException;->error_code:I

    const/4 p1, 0x0

    const/16 v1, 0x9

    if-ne v2, v1, :cond_2

    invoke-static {}, Lcom/perm/kate/KateFloodBackoff;->next()J

    move-result-wide v0

    goto :goto_0

    :cond_2
    const-wide/32 v0, 0x1d4c0

    goto :goto_0

    :cond_1
    const-wide/32 v0, 0xea60

    .line 220
    :goto_0
'''

OLD_READY = '''    .line 186
    :cond_0
    check-cast p1, [Ljava/lang/Object;
'''

NEW_READY = '''    .line 186
    :cond_0
    # f57_flood_backoff: успешный ответ — сбрасываем счётчик
    invoke-static {}, Lcom/perm/kate/KateFloodBackoff;->reset()V

    check-cast p1, [Ljava/lang/Object;
'''

# --- 1) класс backoff -------------------------------------------------------
if os.path.exists(BACKOFF) and MARK in open(BACKOFF, encoding="utf-8").read():
    print("f57 KateFloodBackoff: уже создан")
else:
    open(BACKOFF, "w", encoding="utf-8").write(BACKOFF_SMALI)
    print("f57 KateFloodBackoff: создан")

# --- 2) error() -------------------------------------------------------------
s = open(CALLBACK, encoding="utf-8").read()
if MARK in s:
    print("f57 LongPoll$RequestServerThread$1.error: уже применён")
else:
    if OLD_ERROR not in s:
        raise SystemExit("f57: якорь error() не найден")
    s = s.replace(OLD_ERROR, NEW_ERROR, 1)
    print("f57 LongPoll$RequestServerThread$1.error: пауза при flood добавлена")

# --- 3) ready() -------------------------------------------------------------
if "KateFloodBackoff;->reset()V" in s:
    print("f57 LongPoll$RequestServerThread$1.ready: уже применён")
else:
    if OLD_READY not in s:
        raise SystemExit("f57: якорь ready() не найден")
    s = s.replace(OLD_READY, NEW_READY, 1)
    print("f57 LongPoll$RequestServerThread$1.ready: сброс счётчика добавлен")

open(CALLBACK, "w", encoding="utf-8").write(s)
PYEOF
