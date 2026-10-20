#!/bin/sh
# патч f45 (2026-10-20): максимальная частота обновления экрана.
#
# На телефонах с экраном 90/120/144/165/180 Гц Android по умолчанию может
# держать приложение на 60 Гц, если оно само не просит высокую частоту.
# Патч добавляет в BaseActivity.onResume вызов HighRefreshRate.apply(), который:
#   * (API 23+) находит display mode с максимальной refresh rate;
#   * если есть high-refresh режим с текущим разрешением — выбирает его
#     (preferredDisplayModeId + preferredRefreshRate), иначе просит максимум
#     только через preferredRefreshRate (без смены разрешения);
#   * (API 30+) дополнительно вызывает Window.setFrameRate(maxFps, DEFAULT).
# На экранах 180 Гц приложение запрашивает 180 Гц; на 60 Гц поведение не меняется.
# Все ошибки глушатся (try/catch Throwable), чтобы не уронить Activity.
K="$(dirname "$0")/../"
cd "$K" || exit 1

HELPER="decode/smali/com/perm/kate/HighRefreshRate.smali"
BASE="decode/smali/com/perm/kate/BaseActivity.smali"

if [ ! -f "$HELPER" ]; then
cat > "$HELPER" <<'SMALI'
.class public final Lcom/perm/kate/HighRefreshRate;
.super Ljava/lang/Object;
.source "HighRefreshRate.java"


# direct methods
.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static apply(Landroid/app/Activity;)V
    .locals 12

    :try_start_0
    sget v0, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v1, 0x17

    if-ge v0, v1, :cond_0

    return-void

    :cond_0
    invoke-virtual {p0}, Landroid/app/Activity;->getWindow()Landroid/view/Window;

    move-result-object v0

    if-nez v0, :cond_1

    return-void

    :cond_1
    invoke-virtual {p0}, Landroid/app/Activity;->getWindowManager()Landroid/view/WindowManager;

    move-result-object v1

    if-nez v1, :cond_2

    return-void

    :cond_2
    invoke-interface {v1}, Landroid/view/WindowManager;->getDefaultDisplay()Landroid/view/Display;

    move-result-object v1

    if-nez v1, :cond_3

    return-void

    :cond_3
    invoke-virtual {v1}, Landroid/view/Display;->getSupportedModes()[Landroid/view/Display$Mode;

    move-result-object v2

    if-eqz v2, :cond_4

    array-length v8, v2

    if-nez v8, :cond_5

    :cond_4
    return-void

    :cond_5
    invoke-virtual {v1}, Landroid/view/Display;->getWidth()I

    move-result v11

    invoke-virtual {v1}, Landroid/view/Display;->getHeight()I

    move-result v1

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

    if-ne v0, v1, :loop_inc

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

    if-gtz v0, :cond_6

    return-void

    :cond_6
    invoke-virtual {p0}, Landroid/app/Activity;->getWindow()Landroid/view/Window;

    move-result-object v0

    invoke-virtual {v0}, Landroid/view/Window;->getAttributes()Landroid/view/WindowManager$LayoutParams;

    move-result-object v2

    if-nez v2, :cond_7

    return-void

    :cond_7
    if-gez v7, :cond_8

    iput v7, v2, Landroid/view/WindowManager$LayoutParams;->preferredDisplayModeId:I

    iput v6, v2, Landroid/view/WindowManager$LayoutParams;->preferredRefreshRate:F

    move v4, v6

    goto :cond_9

    :cond_8
    iput v4, v2, Landroid/view/WindowManager$LayoutParams;->preferredRefreshRate:F

    :cond_9
    invoke-virtual {v0, v2}, Landroid/view/Window;->setAttributes(Landroid/view/WindowManager$LayoutParams;)V

    sget v1, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v2, 0x1e

    if-ge v1, v2, :cond_a

    return-void

    :cond_a
    const/4 v1, 0x0

    invoke-virtual {v0, v4, v1}, Landroid/view/Window;->setFrameRate(FI)V
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    return-void

    :catch_0
    move-exception v0

    return-void
.end method
SMALI
    echo "f45: HighRefreshRate.smali — создан"
else
    echo "f45: HighRefreshRate.smali — уже есть"
fi

if ! grep -q "HighRefreshRate" "$BASE"; then
    python3 - <<'PYEOF'
p = "decode/smali/com/perm/kate/BaseActivity.smali"
s = open(p, encoding="utf-8").read()
old = """    .line 961
    invoke-super {p0}, Landroidx/fragment/app/FragmentActivity;->onResume()V

    return-void
.end method"""
new = """    .line 961
    invoke-super {p0}, Landroidx/fragment/app/FragmentActivity;->onResume()V

    invoke-static {p0}, Lcom/perm/kate/HighRefreshRate;->apply(Landroid/app/Activity;)V

    return-void
.end method"""
assert s.count(old) == 1, "f45: якорь onResume не найден/не уникален"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
print("f45: BaseActivity.onResume — вызов добавлен")
PYEOF
else
    echo "f45: BaseActivity.onResume — уже применён"
fi

echo "f45 max refresh rate применён"
