#!/bin/sh
# патч f56 (2026-11-10): служба-якорь всегда скрыта.
#
# Требование: KeepAliveService не должен показывать пользователю уведомление,
# а в настройках приложения не должно быть переключателя «Скрыть службу-якорь».
#
# Что делает патч:
#   1) убирает CheckBoxPreference key_hide_keepalive из preferences.xml
#      и xml-v22/preferences.xml (настройка больше не нужна — скрытие всегда включено);
#   2) KeepAliveService.ensureForeground():
#      - больше не читает key_hide_keepalive;
#      - не создаёт видимый канал kate_keepalive_visible;
#      - удаляет старый видимый канал через deleteNotificationChannel();
#      - всегда использует один канал kate_keepalive_hidden;
#      - канал: IMPORTANCE_NONE (0) — уведомление не показывается вообще,
#        без звука, вибрации, подсветки и значка (setShowBadge(false));
#      - уведомление: setOnlyAlertOnce(true), setShowWhen(false),
#        setDefaults(0), setPriority(PRIORITY_MIN), setLocalOnly(true).
#
# Почему IMPORTANCE_NONE и почему канал kate_keepalive_hidden:
#   Android 13 принудительно поднимает importance FGS-канала с NONE/MIN до LOW
#   (NotificationManagerService: FGS + importance NONE/MIN -> LOW), ЕСЛИ
#   пользователь сам не отключил канал (USER_LOCKED_IMPORTANCE). На этом
#   устройстве канал kate_keepalive_hidden уже был отключён пользователем
#   (importance=0, mUserLockedFields=4), поэтому уведомление не показывалось.
#   Патч переиспользует этот канал: createNotificationChannel() для удалённого
#   канала «восстанавливает» его с прежними настройками (в т.ч. importance=0).
#   Если канал создать заново (другой ID или после очистки данных), система
#   поднимет его до LOW — тогда нужно один раз выключить канал «Kate connection»
#   в системных настройках уведомлений, и он снова станет невидимым.
#
# Ограничение ОС: канал всё равно остаётся в системных настройках уведомлений
# (в выключенном виде) — foreground-служба обязана иметь канал. Полностью
# убрать запись из системных настроек нельзя, не отказавшись от FGS.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
import os

MARK = "f56_keepalive_hidden"

# --- 1) переключатель в настройках уведомлений -------------------------------
for p in ("decode/res/xml/preferences.xml", "decode/res/xml-v22/preferences.xml"):
    if not os.path.exists(p):
        continue
    s = open(p, encoding="utf-8").read()
    lines = s.splitlines(True)
    out = [ln for ln in lines if 'android:key="key_hide_keepalive"' not in ln]
    if len(out) != len(lines):
        open(p, "w", encoding="utf-8").write("".join(out))
        print("f56: %s — переключатель удалён" % p)
    else:
        print("f56: %s — переключателя нет" % p)

# --- 2) KeepAliveService: один скрытый канал ---------------------------------
svc = "decode/smali/com/perm/kate/KeepAliveService.smali"
s = open(svc, encoding="utf-8").read()

method = r'''.method private ensureForeground()V
    .locals 12

    const-string v0, "notification"

    invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/app/NotificationManager;

    const-string v10, "kate_keepalive_hidden"

    sget v1, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v2, 0x1a

    if-lt v1, v2, :cond_channels_done

    const-string v1, "kate_keepalive_visible"

    invoke-virtual {v0, v1}, Landroid/app/NotificationManager;->deleteNotificationChannel(Ljava/lang/String;)V

    const-string v1, "kate_keepalive_quiet"

    invoke-virtual {v0, v1}, Landroid/app/NotificationManager;->deleteNotificationChannel(Ljava/lang/String;)V

    new-instance v1, Landroid/app/NotificationChannel;

    const-string v4, "Kate connection"

    const/4 v5, 0x0

    invoke-direct {v1, v10, v4, v5}, Landroid/app/NotificationChannel;-><init>(Ljava/lang/String;Ljava/lang/CharSequence;I)V

    const/4 v5, 0x0

    const/4 v6, 0x0

    invoke-virtual {v1, v5, v6}, Landroid/app/NotificationChannel;->setSound(Landroid/net/Uri;Landroid/media/AudioAttributes;)V

    invoke-virtual {v1, v6}, Landroid/app/NotificationChannel;->enableVibration(Z)V

    invoke-virtual {v1, v6}, Landroid/app/NotificationChannel;->setShowBadge(Z)V

    invoke-virtual {v1, v6}, Landroid/app/NotificationChannel;->enableLights(Z)V

    invoke-virtual {v0, v1}, Landroid/app/NotificationManager;->createNotificationChannel(Landroid/app/NotificationChannel;)V

    :cond_channels_done
    new-instance v1, Landroid/content/Intent;

    const-class v2, Lcom/perm/kate/MainActivity;

    invoke-direct {v1, p0, v2}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V

    const/4 v2, 0x0

    const/high16 v3, 0x4000000

    invoke-static {p0, v2, v1, v3}, Landroid/app/PendingIntent;->getActivity(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;

    move-result-object v11

    new-instance v1, Landroid/app/Notification$Builder;

    invoke-direct {v1, p0, v10}, Landroid/app/Notification$Builder;-><init>(Landroid/content/Context;Ljava/lang/String;)V

    sget v2, Lcom/perm/kate/R$drawable;->message_notification_icon:I

    invoke-virtual {v1, v2}, Landroid/app/Notification$Builder;->setSmallIcon(I)Landroid/app/Notification$Builder;

    move-result-object v1

    const-string v2, "Kate"

    invoke-virtual {v1, v2}, Landroid/app/Notification$Builder;->setContentTitle(Ljava/lang/CharSequence;)Landroid/app/Notification$Builder;

    move-result-object v1

    const-string v2, "\u0421\u043e\u0435\u0434\u0438\u043d\u0435\u043d\u0438\u0435 \u0430\u043a\u0442\u0438\u0432\u043d\u043e"

    invoke-virtual {v1, v2}, Landroid/app/Notification$Builder;->setContentText(Ljava/lang/CharSequence;)Landroid/app/Notification$Builder;

    move-result-object v1

    invoke-virtual {v1, v11}, Landroid/app/Notification$Builder;->setContentIntent(Landroid/app/PendingIntent;)Landroid/app/Notification$Builder;

    move-result-object v1

    const/4 v2, 0x1

    invoke-virtual {v1, v2}, Landroid/app/Notification$Builder;->setOngoing(Z)Landroid/app/Notification$Builder;

    move-result-object v1

    invoke-virtual {v1, v2}, Landroid/app/Notification$Builder;->setOnlyAlertOnce(Z)Landroid/app/Notification$Builder;

    move-result-object v1

    const/4 v2, 0x0

    invoke-virtual {v1, v2}, Landroid/app/Notification$Builder;->setShowWhen(Z)Landroid/app/Notification$Builder;

    move-result-object v1

    invoke-virtual {v1, v2}, Landroid/app/Notification$Builder;->setDefaults(I)Landroid/app/Notification$Builder;

    move-result-object v1

    const/4 v2, -0x2

    invoke-virtual {v1, v2}, Landroid/app/Notification$Builder;->setPriority(I)Landroid/app/Notification$Builder;

    move-result-object v1

    const/4 v2, 0x1

    invoke-virtual {v1, v2}, Landroid/app/Notification$Builder;->setLocalOnly(Z)Landroid/app/Notification$Builder;

    move-result-object v1

    invoke-virtual {v1}, Landroid/app/Notification$Builder;->build()Landroid/app/Notification;

    move-result-object v1

    const/16 v2, 0x1234

    invoke-virtual {p0, v2, v1}, Landroid/app/Service;->startForeground(ILandroid/app/Notification;)V

    return-void
.end method'''

if 'const-string v10, "kate_keepalive_hidden"' in s and "enableLights" in s and "key_hide_keepalive" not in s:
    print("f56: KeepAliveService.smali — уже применён")
else:
    start = s.index(".method private ensureForeground()V")
    end = s.index(".end method", start) + len(".end method")
    s = s[:start] + method + s[end:]
    open(svc, "w", encoding="utf-8").write(s)
    print("f56: KeepAliveService.smali — один скрытый канал")
PYEOF

echo "f56 keepalive hidden применён"
