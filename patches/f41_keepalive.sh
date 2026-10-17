#!/bin/sh
# патч f41 (Этап E.5, 2026-10-17): сервис-якорь для уведомлений при закрытом приложении.
#
# Симптом: уведомления о новых сообщениях приходят ТОЛЬКО пока жив процесс Kate.
# После свайпа из «недавних» (или am force-stop) процесс убит, LongPoll умирает
# вместе с ним -> уведомлений нет. Обойти это push-каналом не удалось (см. ниже).
#
# Почему не push (закрытые направления, подробности в HISTORY/patches/README):
#   - VK web push (вариант C): регистрация endpoint'а проходит (a_subscribe -> data:[true]),
#     но VK НИКОГДА не шлёт POST на наш endpoint (проверено в т.ч. при закрытом приложении);
#     мобильный service worker (/js/sw.js) вообще без push-обработчика. Тупик.
#   - Нативный FCM: приложение уже имеет FCM-токен и push_registered:true/is_fcm:true,
#     но это проект самого Kate (sender 54740537194, gcm-kate-mobile), а app_id Kate в
#     flood control (account.getInfo -> error 9) -> account.registerDevice не проходит.
#     VK шлёт push только в свои/известные проекты. Тупик.
#   - Android не доставляет FCM приложению, убитому свайпом (помечается stopped) —
#     даже официальному приложению VK. Поэтому единственный надёжный путь — держать
#     собственный процесс живым.
#
# Решение: foreground-сервис (START_STICKY + setOngoing(true)) — пока он foreground,
# процесс Kate не убивается системой за неиспользованием, и её собственный LongPoll
# продолжает работать (именно он приносит уведомления). Работает без push-инфраструктуры.
#
# Фикс (3 правки, идемпотентно):
#   1) создаётся decode/smali/com/perm/kate/KeepAliveService.smali — Service с
#      onCreate/onStartCommand -> ensureForeground(): канал "kate_keepalive" (IMPORTANCE_LOW,
#      Android>=26), ПИ -> MainActivity, setOngoing(true), startForeground(0x1234, ...),
#      START_STICKY; onBind -> null.
#   2) AndroidManifest.xml: объявляется <service android:exported="false"
#      android:name="com.perm.kate.KeepAliveService"/> после OnlineService.
#   3) MainActivity.onCreate: сразу после invoke-super вызывается
#      startService(new Intent(this, KeepAliveService.class)).
#
# Приёмка (устройство OPPO CPH2205, Android 13): isForeground=true, foregroundId=4660,
# сервис выживает `am kill`; LongPoll продолжается (Kate.LongPoll: code=200, message created);
# подтверждено пользователем: после свайпа уведомления о сообщениях приходят.
#
# Замечание: в оригинале приложения нет foreground-сервиса, поэтому при свайпе процесс
# убивался. targetSdk=29 (f4) -> не требуется foregroundServiceType (нужен лишь с Android 13+
# при target>=34) и разрешён запуск FGS из фона. На ColorOS дополнительно рекомендуется
# разрешить автозапуск и снять оптимизацию батареи для kate web.
K="$(dirname "$0")/../"
cd "$K" || exit 1

# --- 1) файл сервиса -----------------------------------------------------------
SVC=decode/smali/com/perm/kate/KeepAliveService.smali
mkdir -p decode/smali/com/perm/kate
cat > "$SVC" <<'SMALI'
.class public Lcom/perm/kate/KeepAliveService;
.super Landroid/app/Service;
.source "KeepAliveService.java"


.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Landroid/app/Service;-><init>()V

    return-void
.end method


.method public onBind(Landroid/content/Intent;)Landroid/os/IBinder;
    .locals 1

    const/4 v0, 0x0

    return-object v0
.end method


.method public onCreate()V
    .locals 0

    invoke-super {p0}, Landroid/app/Service;->onCreate()V

    invoke-direct {p0}, Lcom/perm/kate/KeepAliveService;->ensureForeground()V

    return-void
.end method


.method public onStartCommand(Landroid/content/Intent;II)I
    .locals 1

    invoke-direct {p0}, Lcom/perm/kate/KeepAliveService;->ensureForeground()V

    const/4 v0, 0x1

    return v0
.end method


.method private ensureForeground()V
    .locals 10

    const-string v0, "notification"

    invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/app/NotificationManager;

    sget v1, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v2, 0x1a

    if-lt v1, v2, :cond_channel

    new-instance v1, Landroid/app/NotificationChannel;

    const-string v2, "kate_keepalive"

    const-string v3, "Kate connection"

    const/4 v4, 0x2

    invoke-direct {v1, v2, v3, v4}, Landroid/app/NotificationChannel;-><init>(Ljava/lang/String;Ljava/lang/CharSequence;I)V

    invoke-virtual {v0, v1}, Landroid/app/NotificationManager;->createNotificationChannel(Landroid/app/NotificationChannel;)V

    :cond_channel
    new-instance v1, Landroid/content/Intent;

    const-class v2, Lcom/perm/kate/MainActivity;

    invoke-direct {v1, p0, v2}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V

    const/4 v2, 0x0

    const/high16 v3, 0x4000000

    invoke-static {p0, v2, v1, v3}, Landroid/app/PendingIntent;->getActivity(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;

    move-result-object v1

    new-instance v2, Landroid/app/Notification$Builder;

    const-string v3, "kate_keepalive"

    invoke-direct {v2, p0, v3}, Landroid/app/Notification$Builder;-><init>(Landroid/content/Context;Ljava/lang/String;)V

    sget v3, Lcom/perm/kate/R$drawable;->message_notification_icon:I

    invoke-virtual {v2, v3}, Landroid/app/Notification$Builder;->setSmallIcon(I)Landroid/app/Notification$Builder;

    move-result-object v2

    const-string v3, "Kate"

    invoke-virtual {v2, v3}, Landroid/app/Notification$Builder;->setContentTitle(Ljava/lang/CharSequence;)Landroid/app/Notification$Builder;

    move-result-object v2

    const-string v3, "\u0421\u043e\u0435\u0434\u0438\u043d\u0435\u043d\u0438\u0435 \u0430\u043a\u0442\u0438\u0432\u043d\u043e"

    invoke-virtual {v2, v3}, Landroid/app/Notification$Builder;->setContentText(Ljava/lang/CharSequence;)Landroid/app/Notification$Builder;

    move-result-object v2

    invoke-virtual {v2, v1}, Landroid/app/Notification$Builder;->setContentIntent(Landroid/app/PendingIntent;)Landroid/app/Notification$Builder;

    move-result-object v2

    const/4 v3, 0x1

    invoke-virtual {v2, v3}, Landroid/app/Notification$Builder;->setOngoing(Z)Landroid/app/Notification$Builder;

    move-result-object v2

    const/4 v3, 0x0

    invoke-virtual {v2, v3}, Landroid/app/Notification$Builder;->setShowWhen(Z)Landroid/app/Notification$Builder;

    move-result-object v2

    invoke-virtual {v2}, Landroid/app/Notification$Builder;->build()Landroid/app/Notification;

    move-result-object v2

    const/16 v3, 0x1234

    invoke-virtual {p0, v3, v2}, Landroid/app/Service;->startForeground(ILandroid/app/Notification;)V

    return-void
.end method
SMALI
echo "f41: $SVC записан"

# --- 2) манифест ---------------------------------------------------------------
python3 - <<'EOF'
f = "decode/AndroidManifest.xml"
s = open(f).read()
if "com.perm.kate.KeepAliveService" in s:
    print("f41 manifest: уже применён")
else:
    anchor = '<service android:name="com.perm.kate.OnlineService"/>\n'
    assert s.count(anchor) == 1, "f41: якорь OnlineService не уникален/не найден"
    ins = anchor + '        <service android:exported="false" android:name="com.perm.kate.KeepAliveService"/>\n'
    s = s.replace(anchor, ins, 1)
    open(f, "w").write(s)
    print("f41 manifest OK (<service KeepAliveService/>)")
EOF

# --- 3) MainActivity.onCreate -> startService ----------------------------------
python3 - <<'EOF'
f = "decode/smali/com/perm/kate/MainActivity.smali"
s = open(f).read()
if "Lcom/perm/kate/KeepAliveService;" in s:
    print("f41 MainActivity: уже применён")
    sys_exit = False
else:
    anchor = """    .line 117
    invoke-super {p0, p1}, Lcom/perm/kate/BaseActivity;->onCreate(Landroid/os/Bundle;)V

    .line 120
"""
    assert s.count(anchor) == 1, "f41: якорь MainActivity.onCreate не уникален/не найден"
    hook = """    .line 117
    invoke-super {p0, p1}, Lcom/perm/kate/BaseActivity;->onCreate(Landroid/os/Bundle;)V

    new-instance v0, Landroid/content/Intent;

    const-class v1, Lcom/perm/kate/KeepAliveService;

    invoke-direct {v0, p0, v1}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V

    invoke-virtual {p0, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;

    .line 120
"""
    s = s.replace(anchor, hook, 1)
    open(f, "w").write(s)
    print("f41 MainActivity OK (startService KeepAliveService)")
EOF

echo "f41 keepalive применён"
