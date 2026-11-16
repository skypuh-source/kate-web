#!/bin/sh
# патч f52 (2026-11-11): события прочтения и «печатает» из LongPoll.
#
# Kate не показывает события прочтения и «печатает» из LongPoll. Прочтение
# исходящих приходит типом 7 ([7, peer_id, local_id]) — оригинал уже помечает
# такие сообщения read_state=1, но никак не сообщает пользователю. Типы 61/62
# (печатает в чате/диалоге) не обрабатываются вовсе: оригинал знает только
# 63/64 (аудиосообщения), поэтому индикатор «печатает» в обычной переписке
# не появлялся.
#
# Что делает патч:
#   1) новый класс com.perm.kate.KateEvents:
#      • onRead()   — тип 7: помечает исходящие сообщения диалога прочитанными
#        (read_state=1, message_id <= local_id), обновляет открытый чат через
#        broadcast new_messages и, в зависимости от состояния, показывает тост
#        или тихое уведомление;
#      • onTyping() — типы 61 (диалог) и 62 (беседа): отправляет существующий
#        broadcast typing,
#        который уже умеет показывать «печатает» и сам скрывает его через 6 с;
#      • настройки: key_event_read (события прочтения),
#        key_event_preview_read (имя собеседника в уведомлении),
#        key_event_typing (индикатор «печатает»).
#   2) LongPoll.parseUpdates(): ветки для типов 61 (0x3d) и 62 (0x3e), а
#      onRead() вызывается в начале штатной ветки типа 7 (до
#      setMessagesReadState, чтобы отличить реальное изменение строк).
#      Ветки 61/62 возвращаются в общий :goto_6, остальная обработка не меняется.
#   3) preferences.xml и xml-v22/preferences.xml: три переключателя в разделе
#      «Сообщения».
#
# Важно: в таблице messages chat_id = -peer_id и для личек, и для бесед
# (проверено по базе устройства: uid=106635391 → chat_id=-106635391,
# peer=2217081487 → chat_id=-2217081487).
#
# Поведение прочтения:
#   • галочки обновляются всегда (БД + broadcast), даже если события выключены;
#   • открыт этот чат → тост «Сообщения прочитаны»;
#   • приложение в фоне → тихое уведомление (канал kate_events, IMPORTANCE_LOW,
#     без звука/вибрации/значка);
#   • приложение на экране, но открыт другой чат → только галочки;
#   • первый пакет после переподключения LongPoll (p2=1) обрабатывается молча.
#   Тост/уведомление показываются только если реально изменились строки БД,
#   поэтому повторные события одного и того же прочтения не спамят.
#
# Уведомление создаётся локально, без сети и новых разрешений. На Android < 26
# используется старый Notification.Builder без канала.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
import os

MARK = "f52_events"
BASE = "decode/smali/com/perm/kate/"

KATE_EVENTS = r'''.class public final Lcom/perm/kate/KateEvents;
.super Ljava/lang/Object;
.source "KateEvents.java"


# static fields
.field private static final CHANNEL:Ljava/lang/String; = "kate_events"

.field private static final NOTIF_ID:I = 0x4b41


# direct methods
.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method private static broadcastRefresh()V
    .locals 2

    # f52_events: сообщить открытым экранам, что состояние сообщений изменилось
    new-instance v0, Landroid/content/Intent;

    invoke-direct {v0}, Landroid/content/Intent;-><init>()V

    const-string v1, "com.perm.kate.intent.action.new_messages"

    invoke-virtual {v0, v1}, Landroid/content/Intent;->setAction(Ljava/lang/String;)Landroid/content/Intent;

    sget-object v1, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    invoke-static {v1}, Landroidx/localbroadcastmanager/content/LocalBroadcastManager;->getInstance(Landroid/content/Context;)Landroidx/localbroadcastmanager/content/LocalBroadcastManager;

    move-result-object v1

    invoke-virtual {v1, v0}, Landroidx/localbroadcastmanager/content/LocalBroadcastManager;->sendBroadcast(Landroid/content/Intent;)Z

    return-void
.end method

.method private static readEnabled()Z
    .locals 3

    sget-object v0, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    invoke-static {v0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;

    move-result-object v0

    const-string v1, "key_event_read"

    const/4 v2, 0x1

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getBoolean(Ljava/lang/String;Z)Z

    move-result v0

    return v0
.end method

.method private static typingEnabled()Z
    .locals 3

    sget-object v0, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    invoke-static {v0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;

    move-result-object v0

    const-string v1, "key_event_typing"

    const/4 v2, 0x1

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getBoolean(Ljava/lang/String;Z)Z

    move-result v0

    return v0
.end method

.method private static previewEnabled()Z
    .locals 3

    sget-object v0, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    invoke-static {v0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;

    move-result-object v0

    const-string v1, "key_event_preview_read"

    const/4 v2, 0x1

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getBoolean(Ljava/lang/String;Z)Z

    move-result v0

    return v0
.end method

.method private static inForeground()Z
    .locals 1

    # f52_events: на экране ли приложение (счётчик ActivityLifecycleCallbacks,
    # см. KateFg). getRunningAppProcesses() не годится: у Kate постоянный
    # foreground-service, importance всегда <= 200, и фон считался «на экране».
    sget v0, Lcom/perm/kate/KateFg;->count:I

    if-lez v0, :f52_fg_background

    const/4 v0, 0x1

    return v0

    :f52_fg_background
    const/4 v0, 0x0

    return v0
.end method

.method private static nameFor(JJ)Ljava/lang/String;
    .locals 6

    :try_start_0
    const-wide v0, 0x77359400L

    cmp-long v2, p0, v0

    if-gtz v2, :f52_name_chat

    sget-object v2, Lcom/perm/kate/KApplication;->db:Lcom/perm/kate/db/DataHelper;

    invoke-virtual {v2, p0, p1}, Lcom/perm/kate/db/DataHelper;->fetchUser(J)Lcom/perm/kate/api/User;

    move-result-object v2

    if-eqz v2, :f52_name_empty

    new-instance v3, Ljava/lang/StringBuilder;

    invoke-direct {v3}, Ljava/lang/StringBuilder;-><init>()V

    iget-object v4, v2, Lcom/perm/kate/api/User;->first_name:Ljava/lang/String;

    invoke-virtual {v3, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v4, " "

    invoke-virtual {v3, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    iget-object v4, v2, Lcom/perm/kate/api/User;->last_name:Ljava/lang/String;

    invoke-virtual {v3, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v3}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v2

    return-object v2

    :f52_name_chat
    sub-long v0, p0, v0

    sget-object v2, Lcom/perm/kate/KApplication;->db:Lcom/perm/kate/db/DataHelper;

    invoke-virtual {v2, v0, v1, p2, p3}, Lcom/perm/kate/db/DataHelper;->fetchChatName(JJ)Ljava/lang/CharSequence;

    move-result-object v2

    if-eqz v2, :f52_name_empty

    invoke-virtual {v2}, Ljava/lang/Object;->toString()Ljava/lang/String;

    move-result-object v2

    return-object v2

    :f52_name_empty
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catch_all

    const-string v2, ""

    return-object v2

    :catch_all
    const-string v2, ""

    return-object v2
.end method

.method private static notifyRead(JJ)V
    .locals 10

    :try_start_0
    invoke-static {p0, p1, p2, p3}, Lcom/perm/kate/KateEvents;->nameFor(JJ)Ljava/lang/String;

    move-result-object v0

    invoke-static {}, Lcom/perm/kate/KateEvents;->previewEnabled()Z

    move-result v1

    if-eqz v1, :f52_notify_generic

    invoke-static {v0}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z

    move-result v1

    if-nez v1, :f52_notify_generic

    new-instance v1, Ljava/lang/StringBuilder;

    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V

    invoke-virtual {v1, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v2, " \u043f\u0440\u043e\u0447\u0438\u0442\u0430\u043b(\u0430) \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u044f"

    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v2

    const-string v3, ""

    goto :f52_notify_ready

    :f52_notify_generic
    const-string v2, "\u0421\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u044f \u043f\u0440\u043e\u0447\u0438\u0442\u0430\u043d\u044b"

    const-string v3, "\u0421\u043e\u0431\u0435\u0441\u0435\u0434\u043d\u0438\u043a \u043f\u0440\u043e\u0447\u0438\u0442\u0430\u043b(\u0430) \u0432\u0430\u0448\u0438 \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u044f"

    :f52_notify_ready
    sget-object v4, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    const-string v5, "notification"

    invoke-virtual {v4, v5}, Landroid/app/Application;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v4

    check-cast v4, Landroid/app/NotificationManager;

    sget v5, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v6, 0x1a

    if-lt v5, v6, :f52_notify_new_builder

    new-instance v5, Landroid/app/NotificationChannel;

    const-string v6, "kate_events"

    const-string v7, "\u0421\u043e\u0431\u044b\u0442\u0438\u044f \u0447\u0430\u0442\u043e\u0432"

    const/4 v8, 0x2

    invoke-direct {v5, v6, v7, v8}, Landroid/app/NotificationChannel;-><init>(Ljava/lang/String;Ljava/lang/CharSequence;I)V

    const/4 v6, 0x0

    invoke-virtual {v5, v6, v6}, Landroid/app/NotificationChannel;->setSound(Landroid/net/Uri;Landroid/media/AudioAttributes;)V

    const/4 v7, 0x0

    invoke-virtual {v5, v7}, Landroid/app/NotificationChannel;->enableVibration(Z)V

    invoke-virtual {v5, v7}, Landroid/app/NotificationChannel;->setShowBadge(Z)V

    invoke-virtual {v5, v7}, Landroid/app/NotificationChannel;->enableLights(Z)V

    invoke-virtual {v4, v5}, Landroid/app/NotificationManager;->createNotificationChannel(Landroid/app/NotificationChannel;)V

    new-instance v5, Landroid/app/Notification$Builder;

    sget-object v6, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    const-string v7, "kate_events"

    invoke-direct {v5, v6, v7}, Landroid/app/Notification$Builder;-><init>(Landroid/content/Context;Ljava/lang/String;)V

    goto :f52_notify_builder_ready

    :f52_notify_new_builder
    new-instance v5, Landroid/app/Notification$Builder;

    sget-object v6, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    invoke-direct {v5, v6}, Landroid/app/Notification$Builder;-><init>(Landroid/content/Context;)V

    :f52_notify_builder_ready
    sget v6, Lcom/perm/kate/R$drawable;->message_notification_icon:I

    invoke-virtual {v5, v6}, Landroid/app/Notification$Builder;->setSmallIcon(I)Landroid/app/Notification$Builder;

    move-result-object v5

    invoke-virtual {v5, v2}, Landroid/app/Notification$Builder;->setContentTitle(Ljava/lang/CharSequence;)Landroid/app/Notification$Builder;

    move-result-object v5

    invoke-virtual {v5, v3}, Landroid/app/Notification$Builder;->setContentText(Ljava/lang/CharSequence;)Landroid/app/Notification$Builder;

    move-result-object v5

    const/4 v6, 0x1

    invoke-virtual {v5, v6}, Landroid/app/Notification$Builder;->setAutoCancel(Z)Landroid/app/Notification$Builder;

    move-result-object v5

    invoke-virtual {v5, v6}, Landroid/app/Notification$Builder;->setOnlyAlertOnce(Z)Landroid/app/Notification$Builder;

    move-result-object v5

    const/4 v7, 0x0

    invoke-virtual {v5, v7}, Landroid/app/Notification$Builder;->setDefaults(I)Landroid/app/Notification$Builder;

    move-result-object v5

    const/4 v7, -0x1

    invoke-virtual {v5, v7}, Landroid/app/Notification$Builder;->setPriority(I)Landroid/app/Notification$Builder;

    move-result-object v5

    invoke-virtual {v5}, Landroid/app/Notification$Builder;->build()Landroid/app/Notification;

    move-result-object v5

    const/16 v6, 0x4b41

    invoke-virtual {v4, v6, v5}, Landroid/app/NotificationManager;->notify(ILandroid/app/Notification;)V
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catch_all

    return-void

    :catch_all
    return-void
.end method

.method public static onRead(Lorg/json/JSONArray;Lcom/perm/kate/LongPoll;Z)V
    .locals 16

    # f52_events: тип 7 = [7, peer_id, local_id] — собеседник прочитал наши
    # сообщения. В БД chat_id = -peer_id, поэтому в параметр SQL идёт -peer.
    move-object/from16 v12, p0

    move-object/from16 v13, p1

    const/4 v8, 0x1

    invoke-virtual {v12, v8}, Lorg/json/JSONArray;->optLong(I)J

    move-result-wide v0

    const/4 v8, 0x2

    invoke-virtual {v12, v8}, Lorg/json/JSONArray;->optLong(I)J

    move-result-wide v2

    const-wide/16 v4, 0x0

    cmp-long v8, v2, v4

    if-lez v8, :f52_read_cmid_ok

    move-wide v4, v2

    goto :f52_read_cmid_ready

    :f52_read_cmid_ok
    const-wide v4, 0x7fffffffffffffffL

    :f52_read_cmid_ready
    new-instance v6, Landroid/content/ContentValues;

    invoke-direct {v6}, Landroid/content/ContentValues;-><init>()V

    const-string v8, "read_state"

    const/4 v9, 0x1

    invoke-static {v9}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v10

    invoke-virtual {v6, v8, v10}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/Integer;)V

    sget-object v8, Lcom/perm/kate/KApplication;->db:Lcom/perm/kate/db/DataHelper;

    iget-object v8, v8, Lcom/perm/kate/db/DataHelper;->mDbHelper:Lcom/perm/kate/db/DataHelper$OpenHelper;

    invoke-virtual {v8}, Landroid/database/sqlite/SQLiteOpenHelper;->getWritableDatabase()Landroid/database/sqlite/SQLiteDatabase;

    move-result-object v7

    const/4 v8, 0x5

    new-array v9, v8, [Ljava/lang/String;

    const/4 v8, 0x0

    # f52_events: в messages chat_id = -peer_id (и для личек, и для бесед)
    neg-long v10, v0

    invoke-static {v10, v11}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object v10

    aput-object v10, v9, v8

    const/4 v8, 0x1

    iget-wide v10, v13, Lcom/perm/kate/LongPoll;->account_id:J

    invoke-static {v10, v11}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object v10

    aput-object v10, v9, v8

    const/4 v8, 0x2

    iget-wide v10, v13, Lcom/perm/kate/LongPoll;->group_id:J

    invoke-static {v10, v11}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object v10

    aput-object v10, v9, v8

    const/4 v8, 0x3

    invoke-static {v4, v5}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object v10

    aput-object v10, v9, v8


    const/4 v8, 0x4

    invoke-static {v4, v5}, Ljava/lang/Long;->toString(J)Ljava/lang/String;

    move-result-object v10

    aput-object v10, v9, v8
    const-string v8, "messages"

    const-string v10, "chat_id=? AND account_id=? AND group_id=? AND read_state=0 AND is_out=1 AND ((cmid>0 AND cmid<=?) OR (cmid=0 AND message_id<=?))"

    invoke-virtual {v7, v8, v6, v10, v9}, Landroid/database/sqlite/SQLiteDatabase;->update(Ljava/lang/String;Landroid/content/ContentValues;Ljava/lang/String;[Ljava/lang/String;)I

    move-result v8

    if-lez v8, :f52_read_done

    invoke-static {}, Lcom/perm/kate/KateEvents;->broadcastRefresh()V

    if-nez p2, :f52_read_done

    invoke-static {}, Lcom/perm/kate/KateEvents;->readEnabled()Z

    move-result v8

    if-eqz v8, :f52_read_done

    const-wide v8, 0x77359400L

    cmp-long v10, v0, v8

    if-gtz v10, :f52_read_chat

    sget-wide v10, Lcom/perm/kate/KApplication;->user_in_dialog:J

    cmp-long v14, v10, v0

    if-eqz v14, :f52_read_toast

    goto :f52_read_maybe_notify

    :f52_read_chat
    sub-long v10, v0, v8

    sget-wide v14, Lcom/perm/kate/KApplication;->chat_in_dialog:J

    cmp-long v15, v14, v10

    if-eqz v15, :f52_read_toast

    goto :f52_read_maybe_notify

    :f52_read_toast
    sget-object v8, Lcom/perm/kate/KApplication;->longPoll:Lcom/perm/kate/LongPoll;

    if-eqz v8, :f52_read_done

    new-instance v9, Lcom/perm/kate/KateEvents$ToastRunnable;

    const-string v10, "\u0421\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u044f \u043f\u0440\u043e\u0447\u0438\u0442\u0430\u043d\u044b"

    invoke-direct {v9, v10}, Lcom/perm/kate/KateEvents$ToastRunnable;-><init>(Ljava/lang/String;)V

    iget-object v8, v8, Lcom/perm/kate/LongPoll;->handler:Landroid/os/Handler;

    invoke-virtual {v8, v9}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z

    goto :f52_read_done

    :f52_read_maybe_notify
    invoke-static {}, Lcom/perm/kate/KateEvents;->inForeground()Z

    move-result v8

    if-nez v8, :f52_read_done

    iget-wide v10, v13, Lcom/perm/kate/LongPoll;->account_id:J

    invoke-static {v0, v1, v10, v11}, Lcom/perm/kate/KateEvents;->notifyRead(JJ)V

    :f52_read_done
    return-void
.end method

.method public static onTyping(Lorg/json/JSONArray;IZ)V
    .locals 8

    # f52_events: по документации User Long Poll v3
    #   61 = [61, user_id, flags]    — печатает в диалоге (flags = 1)
    #   62 = [62, user_id, chat_id]  — печатает в беседе (chat_id положительный)
    if-nez p2, :f52_typing_done

    invoke-static {}, Lcom/perm/kate/KateEvents;->typingEnabled()Z

    move-result v0

    if-eqz v0, :f52_typing_done

    const/4 v0, 0x1

    invoke-virtual {p0, v0}, Lorg/json/JSONArray;->optLong(I)J

    move-result-wide v0

    const-wide/16 v2, 0x0

    cmp-long v4, v0, v2

    if-lez v4, :f52_typing_done

    const/16 v4, 0x3d

    if-eq p1, v4, :f52_typing_dialog

    # тип 62: третье поле — id беседы
    const/4 v4, 0x2

    invoke-virtual {p0, v4}, Lorg/json/JSONArray;->optLong(I)J

    move-result-wide v4

    const-wide/16 v2, 0x0

    cmp-long v6, v4, v2

    if-lez v6, :f52_typing_done

    invoke-static {v4, v5}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;

    move-result-object v4

    goto :f52_typing_send

    :f52_typing_dialog
    # тип 61: flags = 0 — перестал печатать
    const/4 v4, 0x2

    invoke-virtual {p0, v4}, Lorg/json/JSONArray;->optInt(I)I

    move-result v4

    if-eqz v4, :f52_typing_done

    const/4 v4, 0x0

    :f52_typing_send
    sget-object v6, Lcom/perm/kate/KApplication;->longPoll:Lcom/perm/kate/LongPoll;

    if-eqz v6, :f52_typing_done

    const/4 v7, 0x0

    invoke-virtual {v6, v0, v1, v4, v7}, Lcom/perm/kate/LongPoll;->sendTypingBroadcast(JLjava/lang/Long;Z)V

    :f52_typing_done
    return-void
.end method
'''

TOAST_RUNNABLE = r'''.class public final Lcom/perm/kate/KateEvents$ToastRunnable;
.super Ljava/lang/Object;
.source "KateEvents.java"


# interfaces
.implements Ljava/lang/Runnable;


# instance fields
.field private final text:Ljava/lang/String;


# direct methods
.method public constructor <init>(Ljava/lang/String;)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    iput-object p1, p0, Lcom/perm/kate/KateEvents$ToastRunnable;->text:Ljava/lang/String;

    return-void
.end method


# virtual methods
.method public run()V
    .locals 3

    sget-object v0, Lcom/perm/kate/KApplication;->current:Landroid/app/Application;

    iget-object v1, p0, Lcom/perm/kate/KateEvents$ToastRunnable;->text:Ljava/lang/String;

    const/4 v2, 0x0

    invoke-static {v0, v1, v2}, Landroid/widget/Toast;->makeText(Landroid/content/Context;Ljava/lang/CharSequence;I)Landroid/widget/Toast;

    move-result-object v0

    invoke-virtual {v0}, Landroid/widget/Toast;->show()V

    return-void
.end method
'''

PATH = BASE + "KateEvents.smali"
TOAST_PATH = BASE + "KateEvents$ToastRunnable.smali"
if os.path.exists(PATH) and MARK in open(PATH, encoding="utf-8").read():
    print("f52 KateEvents: уже создан")
else:
    open(PATH, "w", encoding="utf-8").write(KATE_EVENTS)
    print("f52 KateEvents: создан")

if os.path.exists(TOAST_PATH):
    print("f52 KateEvents$ToastRunnable: уже создан")
else:
    open(TOAST_PATH, "w", encoding="utf-8").write(TOAST_RUNNABLE)
    print("f52 KateEvents$ToastRunnable: создан")

# --- 1b) счётчик видимых активностей -----------------------------------------
FG_PATH = BASE + "KateFg.smali"
if os.path.exists(FG_PATH):
    print("f52 KateFg: уже создан")
else:
    open(FG_PATH, "w", encoding="utf-8").write('''.class public final Lcom/perm/kate/KateFg;
.super Ljava/lang/Object;
.implements Landroid/app/Application$ActivityLifecycleCallbacks;


# static fields
.field public static count:I


# direct methods
.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method


# virtual methods
.method public onActivityCreated(Landroid/app/Activity;Landroid/os/Bundle;)V
    .locals 0

    return-void
.end method

.method public onActivityDestroyed(Landroid/app/Activity;)V
    .locals 0

    return-void
.end method

.method public onActivityPaused(Landroid/app/Activity;)V
    .locals 0

    return-void
.end method

.method public onActivityResumed(Landroid/app/Activity;)V
    .locals 0

    return-void
.end method

.method public onActivitySaveInstanceState(Landroid/app/Activity;Landroid/os/Bundle;)V
    .locals 0

    return-void
.end method

.method public onActivityStarted(Landroid/app/Activity;)V
    .locals 1

    sget v0, Lcom/perm/kate/KateFg;->count:I

    add-int/lit8 v0, v0, 0x1

    sput v0, Lcom/perm/kate/KateFg;->count:I

    return-void
.end method

.method public onActivityStopped(Landroid/app/Activity;)V
    .locals 1

    sget v0, Lcom/perm/kate/KateFg;->count:I

    add-int/lit8 v0, v0, -0x1

    sput v0, Lcom/perm/kate/KateFg;->count:I

    return-void
.end method
''')
    print("f52 KateFg: создан")

# регистрация колбэков в KApplication.onCreate
APP = BASE + "KApplication.smali"
s = open(APP, encoding="utf-8").read()
if "KateFg" in s:
    print("f52 KApplication: уже зарегистрирован")
else:
    APP_ANCHOR = '''    .line 175
    invoke-virtual {p0}, Lcom/perm/kate/KApplication;->enableStrictMode()V

    .line 176
    invoke-super {p0}, Landroid/app/Application;->onCreate()V
'''
    APP_NEW = APP_ANCHOR + '''
    # f52_events: счётчик видимых активностей для «приложение на экране»
    new-instance v0, Lcom/perm/kate/KateFg;

    invoke-direct {v0}, Lcom/perm/kate/KateFg;-><init>()V

    invoke-virtual {p0, v0}, Landroid/app/Application;->registerActivityLifecycleCallbacks(Landroid/app/Application$ActivityLifecycleCallbacks;)V
'''
    assert s.count(APP_ANCHOR) == 1, "f52: якорь KApplication.onCreate не найден/не уникален"
    s = s.replace(APP_ANCHOR, APP_NEW, 1)
    open(APP, "w", encoding="utf-8").write(s)
    print("f52 KApplication: колбэки зарегистрированы")

# --- 2) LongPoll.parseUpdates -------------------------------------------------
LP = BASE + "LongPoll.smali"
s = open(LP, encoding="utf-8").read()

DISPATCH_ANCHOR = '''    .line 387
    const-string v13, "Kate.LongPoll"

    if-eqz v12, :cond_21
'''

DISPATCH_NEW = '''    .line 387
    const-string v13, "Kate.LongPoll"

    # f52_events: 61 — печатает в диалоге, 62 — в беседе. Прочтение — тип 7,
    # в штатной ветке :cond_c (до setMessagesReadState).
    const/16 v4, 0x3d

    if-eq v12, v4, :f52_type_typing61

    const/16 v4, 0x3e

    if-eq v12, v4, :f52_type_typing62

    if-eqz v12, :cond_21
'''

HANDLERS = '''    # f52_events: обработчики новых типов
    :f52_type_typing61
    const/16 v4, 0x3d

    move/from16 v5, p2

    invoke-static {v0, v4, v5}, Lcom/perm/kate/KateEvents;->onTyping(Lorg/json/JSONArray;IZ)V

    goto/16 :goto_6

    :f52_type_typing62
    const/16 v4, 0x3e

    move/from16 v5, p2

    invoke-static {v0, v4, v5}, Lcom/perm/kate/KateEvents;->onTyping(Lorg/json/JSONArray;IZ)V

    goto/16 :goto_6

.end method'''

if MARK in s:
    print("f52 LongPoll: уже применён")
else:
    assert s.count(DISPATCH_ANCHOR) == 1, "f52: якорь диспетчера не найден/не уникален"
    s = s.replace(DISPATCH_ANCHOR, DISPATCH_NEW, 1)

    END_ANCHOR = '''    :cond_29
    :goto_9
    return-void
.end method'''
    assert s.count(END_ANCHOR) == 1, "f52: якорь конца parseUpdates не найден/не уникален"
    s = s.replace(END_ANCHOR, '''    :cond_29
    :goto_9
    return-void

''' + HANDLERS, 1)

    # Тип 7 — штатная ветка прочтения исходящих. Вставляем onRead() перед
    # оригинальным setMessagesReadState: тогда по числу обновлённых строк видно,
    # было ли прочтение новым (иначе повторные события спамили бы тостом).
    TYPE7_ANCHOR = '''    :cond_c
    :try_start_5
    invoke-virtual {v0, v14}, Lorg/json/JSONArray;->getLong(I)J
'''
    TYPE7_NEW = '''    :cond_c
    :try_start_5
    # f52_events: тип 7 = [7, peer_id, local_id] — собеседник прочитал наши сообщения
    move/from16 v5, p2

    invoke-static {v0, v1, v5}, Lcom/perm/kate/KateEvents;->onRead(Lorg/json/JSONArray;Lcom/perm/kate/LongPoll;Z)V

    invoke-virtual {v0, v14}, Lorg/json/JSONArray;->getLong(I)J
'''
    assert s.count(TYPE7_ANCHOR) == 1, "f52: якорь ветки типа 7 не найден/не уникален"
    s = s.replace(TYPE7_ANCHOR, TYPE7_NEW, 1)

    open(LP, "w", encoding="utf-8").write(s)
    print("f52 LongPoll: ветки 61/62 и хук типа 7 добавлены")

# --- 3) настройки -------------------------------------------------------------
PREF_LINES = '''        <CheckBoxPreference android:title="События прочтения" android:key="key_event_read" android:summary="Тост в открытом чате и тихое уведомление в фоне. Галочки обновляются всегда." android:defaultValue="true" />
        <CheckBoxPreference android:title="Имя собеседника в уведомлении" android:key="key_event_preview_read" android:summary="Показывать, кто прочитал сообщения." android:dependency="key_event_read" android:defaultValue="true" />
        <CheckBoxPreference android:title="Показывать «печатает»" android:key="key_event_typing" android:summary="Индикатор набора текста в диалогах и чатах." android:defaultValue="true" />
'''

for p in ("decode/res/xml/preferences.xml", "decode/res/xml-v22/preferences.xml"):
    if not os.path.exists(p):
        continue
    s = open(p, encoding="utf-8").read()
    if "key_event_read" in s:
        print("f52: %s — настройки уже есть" % p)
        continue
    anchor = '        <CheckBoxPreference android:title="@string/typing_status" android:key="key_typing_status" android:summary="@string/typing_status_summary" android:defaultValue="true" />\n'
    assert anchor in s, "f52: якорь настроек не найден в %s" % p
    s = s.replace(anchor, anchor + PREF_LINES, 1)
    open(p, "w", encoding="utf-8").write(s)
    print("f52: %s — настройки добавлены" % p)
PYEOF
