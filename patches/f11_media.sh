#!/bin/sh
# патч f11: доступ к фото устройства (внутренняя галерея пустая).
#
# Причина: сборка идёт с targetSdk 29 (см. f4 — при target>=30 установка падает
# из-за сжатого resources.arsc). Для target<33 на Android 13 действует ЛЕГАСИ-модель
# доступа к медиа: нужно READ_EXTERNAL_STORAGE, а READ_MEDIA_IMAGES системой не
# применяется. Код же (PhotoChooser.chooseFromInternalGallery) на устройстве API>=33
# проверяет/просит именно READ_MEDIA_IMAGES -> разрешение "granted", но MediaStore
# возвращает пусто -> списки альбомов/папок пустые.
#
# Фикс:
#  1) манифест: объявить READ_EXTERNAL_STORAGE;
#  2) PhotoChooser: проверять/просить READ_EXTERNAL_STORAGE (вместо READ_MEDIA_IMAGES)
#     — диалог запроса показывается прямо при клике (проверено на устройстве);
#  3) MainActivity: дополнительно просить READ_EXTERNAL_STORAGE при старте (в onResume,
#     т.к. запрос из onCreate на некоторых OEM тихо отбрасывается), чтобы к моменту
#     клика разрешение уже было выдано и галерея открывалась сразу (у приложения нет
#     onRequestPermissionsResult для кода 100, поэтому после выдачи из клика повторный
#     клик был бы нужен).
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'EOF'
changed = False

# 1) манифест: READ_EXTERNAL_STORAGE
M = "decode/AndroidManifest.xml"
s = open(M).read()
old = '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>\n'
new = old + '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>\n'
if "android.permission.READ_EXTERNAL_STORAGE" in s:
    print("f11: манифест уже пропатчен")
else:
    assert old in s, "f11: WRITE_EXTERNAL_STORAGE в манифесте не найден"
    s = s.replace(old, new, 1)
    open(M, "w").write(s)
    changed = True
    print("f11: манифест -> READ_EXTERNAL_STORAGE")

# 2) PhotoChooser: READ_MEDIA_IMAGES -> READ_EXTERNAL_STORAGE
P = "decode/smali/com/perm/kate/photoupload/PhotoChooser.smali"
s = open(P).read()
old = '    const-string v0, "android.permission.READ_MEDIA_IMAGES"'
new = '    const-string v0, "android.permission.READ_EXTERNAL_STORAGE"'
if old not in s:
    assert new in s, "f11: якорь READ_MEDIA_IMAGES в PhotoChooser не найден"
    print("f11: PhotoChooser уже пропатчен")
else:
    s = s.replace(old, new, 1)
    open(P, "w").write(s)
    changed = True
    print("f11: PhotoChooser -> READ_EXTERNAL_STORAGE")

# 3) MainActivity: requestStoragePermission() + вызов из onResume
A = "decode/smali/com/perm/kate/MainActivity.smali"
s = open(A).read()
if "requestStoragePermission" in s:
    print("f11: MainActivity уже пропатчен")
else:
    anchor = ("    :cond_1\n"
              "    :goto_0\n"
              "    return-void\n"
              ".end method\n")
    add = (anchor +
           "\n"
           ".method public final requestStoragePermission()V\n"
           "    .locals 4\n"
           "\n"
           "    sget v0, Landroid/os/Build$VERSION;->SDK_INT:I\n"
           "\n"
           "    const/16 v1, 0x17\n"
           "\n"
           "    if-ge v0, v1, :done\n"
           "\n"
           "    const-string v0, \"android.permission.READ_EXTERNAL_STORAGE\"\n"
           "\n"
           "    invoke-static {p0, v0}, Landroidx/core/content/ContextCompat;->checkSelfPermission(Landroid/content/Context;Ljava/lang/String;)I\n"
           "\n"
           "    move-result v1\n"
           "\n"
           "    if-eqz v1, :done\n"
           "\n"
           "    const/4 v1, 0x1\n"
           "\n"
           "    new-array v1, v1, [Ljava/lang/String;\n"
           "\n"
           "    const/4 v2, 0x0\n"
           "\n"
           "    aput-object v0, v1, v2\n"
           "\n"
           "    const/16 v3, 0x66\n"
           "\n"
           "    invoke-static {p0, v1, v3}, Landroidx/core/app/ActivityCompat;->requestPermissions(Landroid/app/Activity;[Ljava/lang/String;I)V\n"
           "\n"
           "    :done\n"
           "    return-void\n"
           ".end method\n"
           "\n"
           ".method public onResume()V\n"
           "    .locals 0\n"
           "\n"
           "    invoke-super {p0}, Lcom/perm/kate/BaseActivity;->onResume()V\n"
           "\n"
           "    invoke-virtual {p0}, Lcom/perm/kate/MainActivity;->requestStoragePermission()V\n"
           "\n"
           "    return-void\n"
           ".end method\n")
    assert anchor in s, "f11: якорь конца requestNotificationsPermission не найден"
    s = s.replace(anchor, add, 1)
    open(A, "w").write(s)
    changed = True
    print("f11: MainActivity -> requestStoragePermission (onResume)")

if not changed:
    print("f11: ничего менять не потребовалось")
EOF
