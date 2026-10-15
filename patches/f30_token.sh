#!/bin/sh
# патч f30 (производительность/ускорение): починка кэша токена.
#
# Проблема: WebChannel.getToken минтит при `now + запас >= CACHE_EXP`, а mint (ветка WebMint)
# писал `CACHE_EXP = now + 120с`; запас тоже 120с → условие истинно ВСЕГДА → кэш не работал,
# и КАЖДЫЙ API-запрос поднимал скрытый WebView (WebMint, loadUrl + fetch web_token, до 25 с).
# Замерено 2026-10-15: web_token отдаёт свежий токен с `expires = now + 900с` (15 минут).
#
# Фикс:
#   1) getToken: запас 0x78(120с) -> 0x3c(60с);
#   2) mint (ветка WebMint): назначенный TTL 0x78(120с) -> 0x384(900с).
# Итог: кэш живёт ~840с; минт — раз в ~14 минут вместо каждого запроса.
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/api/WebChannel.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

# --- 1) getToken: запас «до истечения», после div now_sec -> +запас -> сравнить с CACHE_EXP
old1 = """    const-wide/16 v5, 0x78

    add-long/2addr v3, v5

    sget-wide v5, Lcom/perm/kate/api/WebChannel;->CACHE_EXP:J"""
new1 = """    const-wide/16 v5, 0x3c

    add-long/2addr v3, v5

    sget-wide v5, Lcom/perm/kate/api/WebChannel;->CACHE_EXP:J"""

# --- 2) mint (успех WebMint): now_sec + TTL -> CACHE_EXP
old2 = """    const-wide/16 v2, 0x78

    add-long/2addr v4, v2

    sput-wide v4, Lcom/perm/kate/api/WebChannel;->CACHE_EXP:J"""
new2 = """    const-wide/16 v2, 0x384

    add-long/2addr v4, v2

    sput-wide v4, Lcom/perm/kate/api/WebChannel;->CACHE_EXP:J"""

if new1 in s and new2 in s:
    print("f30 WebChannel.smali: уже применён")
    sys.exit(0)

assert old1 in s, "f30: якорь getToken (margin 0x78) не найден"
assert old2 in s, "f30: якорь mint (TTL 0x78) не найден"
assert s.count(old1) == 1, "f30: якорь getToken не уникален"
assert s.count(old2) == 1, "f30: якорь mint не уникален"

s = s.replace(old1, new1, 1)
s = s.replace(old2, new2, 1)
open(f, "w").write(s)
print("f30 WebChannel.smali OK (margin 120->60, TTL 120->900)")
EOF
