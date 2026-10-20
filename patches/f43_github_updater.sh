#!/bin/sh
# патч f43 (2026-10-20): автообновление APK через GitHub Releases.
#
# В приложении уже есть штатный механизм обновления:
#   UpdateChecker.checkSometimes() -> GET version.json -> сравнение code с versionCode;
#   UpdateNotification -> UpdateActivity -> кнопка «Скачать» -> DownloadManager.
# Оба адреса были захардкожены на умерший katemobile.ru, поэтому обновления не работали.
#
# Патч меняет только URL:
#   1) UpdateChecker: version.json берётся из последнего GitHub Release;
#   2) UpdateActivity$2: APK качается из .../releases/latest/download/Kate.apk.
# Имена ассетов фиксированы (version.json и Kate.apk) — их создаёт CI.
#
# Установка APK на Android всё равно требует подтверждения пользователя;
# «тихой» установки без root/device-owner нет. Подпись должна оставаться прежней,
# иначе обновление поверх установленного приложения не встанет.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'EOF'
BASE = "https://github.com/skypuh-source/kate-web/releases/latest/download/"

def patch(path, old, new):
    s = open(path, encoding="utf-8").read()
    if new in s:
        return False
    assert s.count(old) == 1, f"f43: якорь не найден/не уникален в {path}: {old}"
    open(path, "w", encoding="utf-8").write(s.replace(old, new, 1))
    return True

a = patch(
    "decode/smali/com/perm/utils/UpdateChecker.smali",
    '"http://conf.katemobile.ru/conf/version.json"',
    '"%sversion.json"' % BASE,
)
b = patch(
    "decode/smali/com/perm/kate/UpdateActivity$2.smali",
    '"http://katemobile.ru/dl/"',
    '"%s"' % BASE,
)
print("f43: UpdateChecker %s; UpdateActivity %s" % (
    "patched" if a else "already",
    "patched" if b else "already",
))
EOF
