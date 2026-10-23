#!/bin/sh
# патч f44 (2026-10-20): управление уведомлением службы-якоря (KeepAliveService).
#
# В настройках уведомлений:
#   переключатель «Скрыть службу-якорь» — служба продолжает работать foreground,
#   но уведомление уходит в отдельный канал "kate_keepalive_hidden" (без значка
#   в строке состояния, в бесшумных).
#
# Важно: нельзя отключать уведомления канала службы-якоря в системных настройках.
# На части прошивок после этого foreground-служба останавливается, и сообщения
# перестают приходить. Поэтому ссылка на настройки канала из приложения убрана.
# Видимый канал имеет отдельный ID: если старый канал "kate_keepalive" был
# отключён пользователем, после выключения скрытия служба всё равно покажет
# уведомление в новом канале.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
import os

# --- 1) пункты в настройках уведомлений --------------------------------------
# На Android 22+ используется отдельный вариант res/xml-v22/preferences.xml,
# поэтому правим оба файла (если вариант присутствует).
for p in ("decode/res/xml/preferences.xml", "decode/res/xml-v22/preferences.xml"):
    if not os.path.exists(p):
        continue
    s = open(p, encoding="utf-8").read()
    if "key_hide_keepalive" in s:
        print("f44: %s — уже применён" % p)
        continue
    anchor = '        <CheckBoxPreference android:title="@string/running_title" android:key="running_notification" android:summary="@string/running_summary" android:defaultValue="false" />\n'
    assert s.count(anchor) == 1, "f44: якорь running_notification не найден/не уникален в %s" % p
    item = (
        '        <CheckBoxPreference android:title="Скрыть службу-якорь" '
        'android:key="key_hide_keepalive" '
        'android:summary="Служба продолжит работать; уведомление станет тихим и без значка. '
        'Не отключайте уведомления канала в системе — служба может остановиться." '
        'android:defaultValue="false" />\n'
    )
    s = s.replace(anchor, anchor + item, 1)
    open(p, "w", encoding="utf-8").write(s)
    print("f44: %s — пункты добавлены" % p)

# --- 2) KeepAliveService: выбор канала по настройке --------------------------
svc = "decode/smali/com/perm/kate/KeepAliveService.smali"
s = open(svc, encoding="utf-8").read()
if "key_hide_keepalive" not in s:
    start = s.index(".method private ensureForeground()V")
    end = s.index(".end method", start) + len(".end method")
    method = r'''.method private ensureForeground()V
    .locals 12

    invoke-static {p0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;

    move-result-object v0

    const-string v1, "key_hide_keepalive"

    const/4 v2, 0x0

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getBoolean(Ljava/lang/String;Z)Z

    move-result v9

    const-string v0, "notification"

    invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/app/NotificationManager;

    const-string v10, "kate_keepalive_visible"

    sget v1, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v2, 0x1a

    if-lt v1, v2, :cond_channels_done

    new-instance v1, Landroid/app/NotificationChannel;

    const-string v4, "Kate connection"

    const/4 v5, 0x2

    invoke-direct {v1, v10, v4, v5}, Landroid/app/NotificationChannel;-><init>(Ljava/lang/String;Ljava/lang/CharSequence;I)V

    invoke-virtual {v0, v1}, Landroid/app/NotificationManager;->createNotificationChannel(Landroid/app/NotificationChannel;)V

    if-eqz v9, :cond_channels_done

    const-string v10, "kate_keepalive_hidden"

    new-instance v1, Landroid/app/NotificationChannel;

    const-string v4, "Kate connection (hidden)"

    const/4 v5, 0x0

    invoke-direct {v1, v10, v4, v5}, Landroid/app/NotificationChannel;-><init>(Ljava/lang/String;Ljava/lang/CharSequence;I)V

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

    const/4 v2, 0x0

    invoke-virtual {v1, v2}, Landroid/app/Notification$Builder;->setShowWhen(Z)Landroid/app/Notification$Builder;

    move-result-object v1

    if-eqz v9, :cond_priority_hidden

    const/4 v2, -0x1

    goto :cond_priority_apply

    :cond_priority_hidden
    const/4 v2, -0x2

    :cond_priority_apply
    invoke-virtual {v1, v2}, Landroid/app/Notification$Builder;->setPriority(I)Landroid/app/Notification$Builder;

    move-result-object v1

    invoke-virtual {v1}, Landroid/app/Notification$Builder;->build()Landroid/app/Notification;

    move-result-object v1

    const/16 v2, 0x1234

    invoke-virtual {p0, v2, v1}, Landroid/app/Service;->startForeground(ILandroid/app/Notification;)V

    return-void
.end method'''
    s = s[:start] + method + s[end:]
    open(svc, "w", encoding="utf-8").write(s)
    print("f44: KeepAliveService.smali — канал по настройке")
else:
    print("f44: KeepAliveService.smali — уже применён")

# --- 3) слушатель переключателя ---------------------------------------------
lst = "decode/smali/com/perm/kate/Settings$84.smali"
if not os.path.exists(lst):
    body = '''.class public Lcom/perm/kate/Settings$84;
.super Ljava/lang/Object;
.source "Settings.java"

# interfaces
.implements Landroid/preference/Preference$OnPreferenceChangeListener;


# annotations
.annotation system Ldalvik/annotation/EnclosingClass;
    value = Lcom/perm/kate/Settings;
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x1
    name = null
.end annotation


# instance fields
.field public final synthetic this$0:Lcom/perm/kate/Settings;


# direct methods
.method public constructor <init>(Lcom/perm/kate/Settings;)V
    .locals 0

    iput-object p1, p0, Lcom/perm/kate/Settings$84;->this$0:Lcom/perm/kate/Settings;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method


# virtual methods
.method public onPreferenceChange(Landroid/preference/Preference;Ljava/lang/Object;)Z
    .locals 3

    iget-object v0, p0, Lcom/perm/kate/Settings$84;->this$0:Lcom/perm/kate/Settings;

    invoke-static {v0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;

    move-result-object v0

    invoke-interface {v0}, Landroid/content/SharedPreferences;->edit()Landroid/content/SharedPreferences$Editor;

    move-result-object v0

    const-string v1, "key_hide_keepalive"

    check-cast p2, Ljava/lang/Boolean;

    invoke-virtual {p2}, Ljava/lang/Boolean;->booleanValue()Z

    move-result v2

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences$Editor;->putBoolean(Ljava/lang/String;Z)Landroid/content/SharedPreferences$Editor;

    move-result-object v0

    invoke-interface {v0}, Landroid/content/SharedPreferences$Editor;->apply()V

    iget-object v0, p0, Lcom/perm/kate/Settings$84;->this$0:Lcom/perm/kate/Settings;

    new-instance v1, Landroid/content/Intent;

    const-class p2, Lcom/perm/kate/KeepAliveService;

    invoke-direct {v1, v0, p2}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V

    invoke-virtual {v0, v1}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;

    const/4 p1, 0x1

    return p1
.end method
'''
    open(lst, "w", encoding="utf-8").write(body)
    print("f44: Settings$84.smali — создан")
else:
    print("f44: Settings$84.smali — уже есть")

# --- 4) подключение слушателя в Settings.onCreate ---------------------------
st = "decode/smali/com/perm/kate/Settings.smali"
s = open(st, encoding="utf-8").read()
if "key_hide_keepalive" not in s:
    anchor = '''    :cond_33
    sget v2, Lcom/perm/kate/R$string;->key_old_style_news:I
'''
    assert s.count(anchor) == 1, "f44: якорь cond_33/key_old_style_news не найден/не уникален"
    hook = '''    :cond_33
    const-string v2, "key_hide_keepalive"

    invoke-virtual {v1, v2}, Landroid/preference/PreferenceActivity;->findPreference(Ljava/lang/CharSequence;)Landroid/preference/Preference;

    move-result-object v2

    if-eqz v2, :cond_f44

    new-instance v8, Lcom/perm/kate/Settings$84;

    invoke-direct {v8, v1}, Lcom/perm/kate/Settings$84;-><init>(Lcom/perm/kate/Settings;)V

    invoke-virtual {v2, v8}, Landroid/preference/Preference;->setOnPreferenceChangeListener(Landroid/preference/Preference$OnPreferenceChangeListener;)V

    :cond_f44
    sget v2, Lcom/perm/kate/R$string;->key_old_style_news:I
'''
    s = s.replace(anchor, hook, 1)
    open(st, "w", encoding="utf-8").write(s)
    print("f44: Settings.smali — слушатель подключён")
else:
    print("f44: Settings.smali — уже применён")
PYEOF

echo "f44 hide keepalive применён"
