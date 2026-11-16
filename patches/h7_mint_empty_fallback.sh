#!/bin/sh
# h7_mint_empty_fallback.sh — исправление пустого токена WebMint (этап H).
#
# Проблема: WebMint.mint() при ошибке JS возвращает пустую строку "", а не null.
# WebChannel.mint() проверял только null (if-eqz v7) и кэшировал "" как токен
# на 900 секунд. Api.sendRequest при length()==0 не добавляет access_token
# в Params, поэтому все запросы шли без токена → error 5 → Session делал
# refresh(), снова получал "" и показывал LoginNotification.
#
# Решение: пустой результат WebMint считается неудачей, управление уходит
# в cookies-fallback (login.vk.ru/?act=web_token). Cookies-путь проверен
# 2026-11-11: remixsid 88 символов → type=okay + свежий access_token.
#
# Не входит в цепочку f*: запускается вручную.
#   sh patches/h7_mint_empty_fallback.sh
# Идемпотентен: повторный запуск ничего не дублирует.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
MARK = "# h7_mint_empty_fallback"
PATH = "decode/smali/com/perm/kate/api/WebChannel.smali"

s = open(PATH, encoding="utf-8").read()
if MARK in s:
    print("h7: уже применён")
    raise SystemExit(0)

anchor = """    if-eqz v7, :goto_old_path
"""
block = """    if-eqz v7, :goto_old_path

    # h7_mint_empty_fallback: WebMint может вернуть "" вместо null
    invoke-virtual {v7}, Ljava/lang/String;->length()I

    move-result v1

    if-nez v1, :goto_old_path
"""

if s.count(anchor) != 1:
    raise SystemExit("h7: якорь не найден/не уникален (%d)" % s.count(anchor))

s = s.replace(anchor, block, 1)
open(PATH, "w", encoding="utf-8").write(s)
print("h7: применён к", PATH)
PYEOF
