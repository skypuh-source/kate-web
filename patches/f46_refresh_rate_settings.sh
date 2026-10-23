#!/bin/sh
# патч f46 (2026-10-20): настройки частоты обновления (развитие f45).
#
# В «Настройках интерфейса»:
#   • «Максимальная частота обновления» (key_max_refresh_rate, по умолчанию вкл.) —
#     запрашивать максимальный display mode; выключение возвращает системное поведение.
#   • «Не менять разрешение» (key_keep_resolution, по умолчанию выкл.) — не переключать
#     экран на более низкое разрешение ради высокой частоты: выбирается максимальная
#     частота среди режимов с максимальным разрешением (native).
#
# Патч f45 создаёт HighRefreshRate и вызывает его из BaseActivity.onResume. f46
# переписывает helper так, чтобы он читал настройки, умел сбрасывать hints и
# сохранять разрешение, а также добавляет слушатель переключателей и вызов из
# Settings.onStart (Settings не наследует BaseActivity).
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
import os

# --- 1) helper HighRefreshRate: настройки, сброс, сохранение разрешения --------
helper = "decode/smali/com/perm/kate/HighRefreshRate.smali"
if not os.path.exists(helper):
    raise SystemExit("f46: нет %s — сначала примените f45" % helper)
s = open(helper, encoding="utf-8").read()
if "key_max_refresh_rate" not in s:
    body = r'''.class public final Lcom/perm/kate/HighRefreshRate;
.super Ljava/lang/Object;
.source "HighRefreshRate.java"


# direct methods
.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static apply(Landroid/app/Activity;)V
    .locals 4

    :try_start_0
    sget v0, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v1, 0x17

    if-ge v0, v1, :cond_0

    return-void

    :cond_0
    invoke-static {p0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;

    move-result-object v0

    const-string v1, "key_max_refresh_rate"

    const/4 v2, 0x1

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getBoolean(Ljava/lang/String;Z)Z

    move-result v1

    if-nez v1, :cond_enabled

    invoke-static {p0}, Lcom/perm/kate/HighRefreshRate;->reset(Landroid/app/Activity;)V

    return-void

    :cond_enabled
    const-string v1, "key_keep_resolution"

    const/4 v2, 0x0

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getBoolean(Ljava/lang/String;Z)Z

    move-result v1

    invoke-static {p0, v1}, Lcom/perm/kate/HighRefreshRate;->applyEnabled(Landroid/app/Activity;Z)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return-void

    :catch_0
    move-exception v0

    return-void
.end method

.method private static reset(Landroid/app/Activity;)V
    .locals 4

    :try_start_0
    invoke-virtual {p0}, Landroid/app/Activity;->getWindow()Landroid/view/Window;

    move-result-object v0

    if-nez v0, :cond_0

    return-void

    :cond_0
    invoke-virtual {v0}, Landroid/view/Window;->getAttributes()Landroid/view/WindowManager$LayoutParams;

    move-result-object v1

    if-nez v1, :cond_1

    return-void

    :cond_1
    const/4 v2, 0x0

    iput v2, v1, Landroid/view/WindowManager$LayoutParams;->preferredDisplayModeId:I

    const/4 v3, 0x0

    iput v3, v1, Landroid/view/WindowManager$LayoutParams;->preferredRefreshRate:F

    invoke-virtual {v0, v1}, Landroid/view/Window;->setAttributes(Landroid/view/WindowManager$LayoutParams;)V

    sget v1, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v2, 0x1e

    if-ge v1, v2, :cond_2

    return-void

    :cond_2
    const/4 v1, 0x0

    const/4 v2, 0x0

    invoke-virtual {v0, v1, v2}, Landroid/view/Window;->setFrameRate(FI)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return-void

    :catch_0
    move-exception v0

    return-void
.end method

.method private static applyEnabled(Landroid/app/Activity;Z)V
    .locals 14

    :try_start_0
    invoke-virtual {p0}, Landroid/app/Activity;->getWindow()Landroid/view/Window;

    move-result-object v0

    if-nez v0, :cond_0

    return-void

    :cond_0
    invoke-virtual {p0}, Landroid/app/Activity;->getWindowManager()Landroid/view/WindowManager;

    move-result-object v1

    if-nez v1, :cond_1

    return-void

    :cond_1
    invoke-interface {v1}, Landroid/view/WindowManager;->getDefaultDisplay()Landroid/view/Display;

    move-result-object v1

    if-nez v1, :cond_2

    return-void

    :cond_2
    invoke-virtual {v1}, Landroid/view/Display;->getSupportedModes()[Landroid/view/Display$Mode;

    move-result-object v2

    if-eqz v2, :cond_3

    array-length v8, v2

    if-nez v8, :cond_4

    :cond_3
    return-void

    :cond_4
    invoke-virtual {v1}, Landroid/view/Display;->getWidth()I

    move-result v11

    invoke-virtual {v1}, Landroid/view/Display;->getHeight()I

    move-result v12

    const/4 v3, 0x0

    const/4 v4, 0x0

    const/4 v5, -0x1

    const/4 v6, 0x0

    const/4 v7, -0x1

    :loop
    if-ge v3, v8, :done

    aget-object v10, v2, v3

    invoke-virtual {v10}, Landroid/view/Display$Mode;->getRefreshRate()F

    move-result v9

    cmpl-float v0, v9, v4

    if-lez v0, :next

    move v4, v9

    invoke-virtual {v10}, Landroid/view/Display$Mode;->getModeId()I

    move-result v5

    :next
    invoke-virtual {v10}, Landroid/view/Display$Mode;->getPhysicalWidth()I

    move-result v0

    if-ne v0, v11, :loop_inc

    invoke-virtual {v10}, Landroid/view/Display$Mode;->getPhysicalHeight()I

    move-result v0

    if-ne v0, v12, :loop_inc

    cmpl-float v0, v9, v6

    if-lez v0, :loop_inc

    move v6, v9

    invoke-virtual {v10}, Landroid/view/Display$Mode;->getModeId()I

    move-result v7

    :loop_inc
    add-int/lit8 v3, v3, 0x1

    goto :loop

    :done
    const/4 v0, 0x0

    cmpl-float v0, v4, v0

    if-gtz v0, :cond_5

    return-void

    :cond_5
    if-nez p1, :keep_resolution

    if-gez v7, :default_ready

    move v4, v6

    move v5, v7

    :default_ready
    goto :have_mode

    :keep_resolution
    const/4 v13, 0x0

    const/4 v3, 0x0

    :pix_loop
    if-ge v3, v8, :pix_done

    aget-object v10, v2, v3

    invoke-virtual {v10}, Landroid/view/Display$Mode;->getPhysicalWidth()I

    move-result v0

    invoke-virtual {v10}, Landroid/view/Display$Mode;->getPhysicalHeight()I

    move-result v9

    mul-int/2addr v0, v9

    if-le v0, v13, :pix_next

    move v13, v0

    :pix_next
    add-int/lit8 v3, v3, 0x1

    goto :pix_loop

    :pix_done
    const/4 v4, 0x0

    const/4 v5, -0x1

    const/4 v3, 0x0

    :native_loop
    if-ge v3, v8, :native_done

    aget-object v10, v2, v3

    invoke-virtual {v10}, Landroid/view/Display$Mode;->getPhysicalWidth()I

    move-result v0

    invoke-virtual {v10}, Landroid/view/Display$Mode;->getPhysicalHeight()I

    move-result v9

    mul-int/2addr v0, v9

    if-ne v0, v13, :native_next

    invoke-virtual {v10}, Landroid/view/Display$Mode;->getRefreshRate()F

    move-result v9

    cmpl-float v0, v9, v4

    if-lez v0, :native_next

    move v4, v9

    invoke-virtual {v10}, Landroid/view/Display$Mode;->getModeId()I

    move-result v5

    :native_next
    add-int/lit8 v3, v3, 0x1

    goto :native_loop

    :native_done
    const/4 v0, 0x0

    cmpl-float v0, v4, v0

    if-gtz v0, :have_mode

    return-void

    :have_mode
    invoke-virtual {p0}, Landroid/app/Activity;->getWindow()Landroid/view/Window;

    move-result-object v0

    invoke-virtual {v0}, Landroid/view/Window;->getAttributes()Landroid/view/WindowManager$LayoutParams;

    move-result-object v13

    if-nez v13, :cond_6

    return-void

    :cond_6
    if-gez v5, :only_rate

    iput v5, v13, Landroid/view/WindowManager$LayoutParams;->preferredDisplayModeId:I

    :only_rate
    iput v4, v13, Landroid/view/WindowManager$LayoutParams;->preferredRefreshRate:F

    invoke-virtual {v0, v13}, Landroid/view/Window;->setAttributes(Landroid/view/WindowManager$LayoutParams;)V

    sget v1, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v2, 0x1e

    if-ge v1, v2, :cond_7

    return-void

    :cond_7
    const/4 v1, 0x0

    invoke-virtual {v0, v4, v1}, Landroid/view/Window;->setFrameRate(FI)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return-void

    :catch_0
    move-exception v0

    return-void
.end method
'''
    open(helper, "w", encoding="utf-8").write(body)
    print("f46: HighRefreshRate.smali — настройки/сброс/разрешение")
else:
    print("f46: HighRefreshRate.smali — уже применён")

# --- 2) пункты в «Настройках интерфейса» -------------------------------------
for p in ("decode/res/xml/preferences.xml", "decode/res/xml-v22/preferences.xml"):
    if not os.path.exists(p):
        continue
    s = open(p, encoding="utf-8").read()
    if "key_max_refresh_rate" in s:
        print("f46: %s — уже применён" % p)
        continue
    anchor = '        <ListPreference android:entries="@array/language" android:title="@string/language" android:key="key_language" android:defaultValue="0" android:entryValues="@array/language_values" />\n'
    assert s.count(anchor) == 1, "f46: якорь key_language не найден/не уникален в %s" % p
    items = (
        '        <CheckBoxPreference android:title="Максимальная частота обновления" '
        'android:key="key_max_refresh_rate" '
        'android:summary="Запрашивать максимальную частоту экрана (до 180 Гц). '
        'Может увеличить расход батареи." android:defaultValue="true" />\n'
        '        <CheckBoxPreference android:title="Не менять разрешение" '
        'android:key="key_keep_resolution" '
        'android:summary="Не переключать экран на более низкое разрешение ради высокой частоты." '
        'android:dependency="key_max_refresh_rate" android:defaultValue="false" />\n'
    )
    s = s.replace(anchor, items + anchor, 1)
    open(p, "w", encoding="utf-8").write(s)
    print("f46: %s — пункты добавлены" % p)

# --- 3) слушатель переключателей --------------------------------------------
lst = "decode/smali/com/perm/kate/Settings$85.smali"
if not os.path.exists(lst):
    body = '''.class public Lcom/perm/kate/Settings$85;
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

    iput-object p1, p0, Lcom/perm/kate/Settings$85;->this$0:Lcom/perm/kate/Settings;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method


# virtual methods
.method public onPreferenceChange(Landroid/preference/Preference;Ljava/lang/Object;)Z
    .locals 4

    iget-object v0, p0, Lcom/perm/kate/Settings$85;->this$0:Lcom/perm/kate/Settings;

    invoke-static {v0}, Landroid/preference/PreferenceManager;->getDefaultSharedPreferences(Landroid/content/Context;)Landroid/content/SharedPreferences;

    move-result-object v0

    invoke-interface {v0}, Landroid/content/SharedPreferences;->edit()Landroid/content/SharedPreferences$Editor;

    move-result-object v0

    invoke-virtual {p1}, Landroid/preference/Preference;->getKey()Ljava/lang/String;

    move-result-object v1

    check-cast p2, Ljava/lang/Boolean;

    invoke-virtual {p2}, Ljava/lang/Boolean;->booleanValue()Z

    move-result v2

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences$Editor;->putBoolean(Ljava/lang/String;Z)Landroid/content/SharedPreferences$Editor;

    move-result-object v0

    invoke-interface {v0}, Landroid/content/SharedPreferences$Editor;->apply()V

    iget-object v0, p0, Lcom/perm/kate/Settings$85;->this$0:Lcom/perm/kate/Settings;

    invoke-static {v0}, Lcom/perm/kate/HighRefreshRate;->apply(Landroid/app/Activity;)V

    const/4 v0, 0x1

    return v0
.end method
'''
    open(lst, "w", encoding="utf-8").write(body)
    print("f46: Settings$85.smali — создан")
else:
    print("f46: Settings$85.smali — уже есть")

# --- 4) подключение слушателей и вызов из onStart ---------------------------
st = "decode/smali/com/perm/kate/Settings.smali"
s = open(st, encoding="utf-8").read()
if "key_max_refresh_rate" not in s:
    anchor = '''    :cond_f44
    sget v2, Lcom/perm/kate/R$string;->key_old_style_news:I
'''
    assert s.count(anchor) == 1, "f46: якорь f44 не найден/не уникален"
    hook = '''    :cond_f44
    const-string v2, "key_max_refresh_rate"

    invoke-virtual {v1, v2}, Landroid/preference/PreferenceActivity;->findPreference(Ljava/lang/CharSequence;)Landroid/preference/Preference;

    move-result-object v2

    if-eqz v2, :cond_f46a

    new-instance v8, Lcom/perm/kate/Settings$85;

    invoke-direct {v8, v1}, Lcom/perm/kate/Settings$85;-><init>(Lcom/perm/kate/Settings;)V

    invoke-virtual {v2, v8}, Landroid/preference/Preference;->setOnPreferenceChangeListener(Landroid/preference/Preference$OnPreferenceChangeListener;)V

    :cond_f46a
    const-string v2, "key_keep_resolution"

    invoke-virtual {v1, v2}, Landroid/preference/PreferenceActivity;->findPreference(Ljava/lang/CharSequence;)Landroid/preference/Preference;

    move-result-object v2

    if-eqz v2, :cond_f46b

    new-instance v8, Lcom/perm/kate/Settings$85;

    invoke-direct {v8, v1}, Lcom/perm/kate/Settings$85;-><init>(Lcom/perm/kate/Settings;)V

    invoke-virtual {v2, v8}, Landroid/preference/Preference;->setOnPreferenceChangeListener(Landroid/preference/Preference$OnPreferenceChangeListener;)V

    :cond_f46b
    sget v2, Lcom/perm/kate/R$string;->key_old_style_news:I
'''
    s = s.replace(anchor, hook, 1)
    print("f46: Settings.smali — слушатели подключены")
else:
    print("f46: Settings.smali — уже применён")

anchor = '''    .line 873
    invoke-super {p0}, Landroid/preference/PreferenceActivity;->onStart()V
'''
if "HighRefreshRate;->apply" not in s:
    assert s.count(anchor) == 1, "f46: якорь Settings.onStart не найден/не уникален"
    s = s.replace(anchor, anchor + '''
    invoke-static {p0}, Lcom/perm/kate/HighRefreshRate;->apply(Landroid/app/Activity;)V
''', 1)
    open(st, "w", encoding="utf-8").write(s)
    print("f46: Settings.onStart — вызов HighRefreshRate.apply")
else:
    print("f46: Settings.onStart — уже применён")
PYEOF

echo "f46 refresh rate settings применён"
