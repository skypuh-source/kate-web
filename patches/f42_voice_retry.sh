#!/bin/sh
# патч f42 (2026-10-20): авто-retry загрузки документов/голосовых.
#
# Симптом: голосовое записывается, но при отправке — «ошибка загрузки».
# Фото и файлы при этом отправляются нормально.
#
# Диагностика (лог устройства + проверки с хоста):
#   docs.getMessagesUploadServer?type=audio_message -> 200, upload_url выдан;
#   POST на pu.vk.ru/c<server>/upload.php -> HTTP 504 (HTML «temporarily unavailable»),
#   приложение кидает FileNotFoundException из PhotoUploader.getInputStream().
#   Тот же файл (вытащен из files/audiocomments/audiocomment.3gp, AAC 16 кГц в 3GP)
#   с того же IP успешно грузится, если попадёт на «хороший» upload-сервер.
#
# Причина: VK отдаёт upload-серверы из двух пулов. Старый пул (c51x..c53x,
# act=add_doc_new) детерминированно отвечает 504 на audio_message; новый (c87x..c90x)
# принимает файл. Выбор сервера случаен (~20-40% «хороших»), приложение делает
# ровно одну попытку -> чаще всего попадает на старый пул и показывает ошибку.
# Фото ходят в новый пул (c85x..c90x, act=do_add) и поэтому работают всегда.
# На одном и том же URL поведение стабильно: bad x3 -> 504/504/504, good x3 -> 200/200/200.
#
# Решение: в DocUploader.uploadPhoto при исключении (504/JSON без file) не показывать
# ошибку сразу, а перезапросить upload-сервер (getUploadServer -> новый upload_url)
# и повторить, до 25 раз. После исчерпания попыток — прежний путь displayError().
# Затрагивает только DocUploader (документы + голосовые), фото-путь не меняется.
#
# Приёмка: отправить голосовое на устройстве; в logcat видно
#   Kate.DocUploader: retry upload N
# и затем успешную отправку (без тоста об ошибке).
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'EOF'
f = "decode/smali/com/perm/kate/photoupload/DocUploader.smali"
s = open(f).read()
changed = False

# --- 1) счётчик попыток --------------------------------------------------------
if "retryCount:I" not in s:
    anchor = ".field public notification:Lcom/perm/kate/notifications/PhotoUploadNotification;\n"
    assert s.count(anchor) == 1, "f42: якорь поля notification не уникален/не найден"
    s = s.replace(
        anchor,
        anchor + "\n.field public retryCount:I\n",
        1,
    )
    changed = True

# --- 2) перед штатным error-путём проверяем лимит попыток ----------------------
anchor = """    .line 116
    :goto_1
    invoke-virtual {p0}, Lcom/perm/kate/photoupload/DocUploader;->displayError()V
"""
if ":f42_retry" not in s:
    assert s.count(anchor) == 1, "f42: якорь :goto_1 не уникален/не найден"
    s = s.replace(
        anchor,
        """    .line 116
    :goto_1
    iget v2, p0, Lcom/perm/kate/photoupload/DocUploader;->retryCount:I

    const/16 v3, 0x19

    if-lt v2, v3, :f42_retry

    invoke-virtual {p0}, Lcom/perm/kate/photoupload/DocUploader;->displayError()V
""",
        1,
    )
    changed = True

# --- 3) блок повтора: новый upload-server и выход ------------------------------
anchor2 = """    invoke-virtual {p1, v0}, Landroid/app/Activity;->runOnUiThread(Ljava/lang/Runnable;)V

    return-void
.end method
"""
if "retry upload " not in s:
    assert s.count(anchor2) == 1, "f42: якорь конца uploadPhoto не уникален/не найден"
    s = s.replace(
        anchor2,
        """    invoke-virtual {p1, v0}, Landroid/app/Activity;->runOnUiThread(Ljava/lang/Runnable;)V

    return-void

    :f42_retry
    add-int/lit8 v2, v2, 0x1

    iput v2, p0, Lcom/perm/kate/photoupload/DocUploader;->retryCount:I

    new-instance v3, Ljava/lang/StringBuilder;

    const-string v4, "retry upload "

    invoke-direct {v3, v4}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    invoke-virtual {v3, v2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    invoke-virtual {v3}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v2

    const-string v3, "Kate.DocUploader"

    invoke-static {v3, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    invoke-virtual {p0}, Lcom/perm/kate/photoupload/DocUploader;->getUploadServer()V

    return-void
.end method
""",
        1,
    )
    changed = True

# --- 4) самокоррекция уже применённого (был баг: if-ge вместо if-lt) ------------
if "if-ge v2, v3, :f42_retry" in s:
    s = s.replace("if-ge v2, v3, :f42_retry", "if-lt v2, v3, :f42_retry")
    changed = True

if changed:
    open(f, "w").write(s)
    print("f42: DocUploader.smali обновлён (retry upload до 25 попыток)")
else:
    print("f42: уже применён")
EOF

echo "f42 voice retry применён"
