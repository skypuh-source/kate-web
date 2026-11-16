#!/bin/sh
# h10_web_token_mint.sh — рабочий cookie-mint web-токена (этап H).
#
# Что было не так:
#   1) mint() читал тело ответа login.vk.ru через BufferedReader.readLine() и
#      получал пустую строку при непустом Content-Length (проверено на устройстве:
#      cl=23, first byte=123 '{', но readLine() → null). Из-за этого cookie-mint
#      всегда падал в catch, и web-токен не добывался.
#   2) getToken() проверял кэш наоборот: при валидном кэше (now+60 < CACHE_EXP)
#      уходил в mint, а при истёкшем — отдавал старый токен. В итоге mint
#      вызывался на КАЖДЫЙ запрос (и каждый раз поднимал WebView на ~4 с).
#   3) mint() сначала запускал WebMint (скрытый WebView), и только потом пробовал
#      cookies. WebView медленный, а его токен не нужен: cookie-mint отдаёт
#      обычный web-токен (expires = now + 900 с), который VK не флудит.
#
# Что делает:
#   • при непустых cookies сразу идёт в cookie-ветку, WebMint остаётся
#     fallback'ом на случай пустых cookies;
#   • читает тело байтами (ByteArrayOutputStream + read(byte[])), с поддержкой
#     gzip — как в рабочем Api.sendRequest;
#   • чинит условие кэша: истёк → mint, валиден → вернуть сохранённый токен.
#
# Не входит в цепочку f*: запускается после f* (см. scripts/apply.sh).
#   sh patches/h10_web_token_mint.sh
# Идемпотентен: повторный запуск ничего не дублирует.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
MARK = "# h10"
PATH = "decode/smali/com/perm/kate/api/WebChannel.smali"

s = open(PATH, encoding="utf-8").read()
if MARK in s:
    print("h10: уже применён")
    raise SystemExit(0)

# --- 1) getToken: правильное условие кэша -------------------------------
old_cache = """    cmp-long v2, v3, v5

    if-ltz v2, :cond_hit
"""
new_cache = """    cmp-long v2, v3, v5

    # h10: кэш валиден (now+60 < CACHE_EXP) → отдаём сохранённый токен,
    # истёк — уходим в mint
    if-ltz v2, :cond_mint

    return-object v0
"""
if s.count(old_cache) != 1:
    raise SystemExit("h10: якорь getToken не найден/не уникален (%d)" % s.count(old_cache))
s = s.replace(old_cache, new_cache, 1)

# --- 2) mint: при непустых cookies сразу cookie-ветка -------------------
old_head = """.method private static mint()Ljava/lang/String;
    .locals 8
"""
new_head = """.method private static mint()Ljava/lang/String;
    .locals 8

    # h10: cookies есть → сразу cookie-mint, без скрытого WebView (WebMint)
    invoke-static {}, Lcom/perm/kate/api/WebChannel;->cookies()Ljava/lang/String;

    move-result-object v0

    invoke-virtual {v0}, Ljava/lang/String;->length()I

    move-result v1

    if-lez v1, :h10_webmint

    goto :goto_old_path

    :h10_webmint
"""
if s.count(old_head) != 1:
    raise SystemExit("h10: якорь mint() не найден/не уникален (%d)" % s.count(old_head))
s = s.replace(old_head, new_head, 1)

# --- 3) чтение тела байтами --------------------------------------------
start = s.index("    :goto_stream\n")
end = s.index("    new-instance v3, Lorg/json/JSONObject;", start)
old_read = s[start:end]
if "readLine" not in old_read:
    raise SystemExit("h10: не найден блок чтения через readLine")

new_read = """    :goto_stream
    # h10: читаем тело байтами (readLine() возвращал null при непустом теле)
    if-eqz v2, :goto_ret_cache

    const-string v5, "Content-Encoding"

    invoke-virtual {v1, v5}, Ljava/net/URLConnection;->getHeaderField(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v5

    if-eqz v5, :h10_no_gzip

    const-string v4, "gzip"

    invoke-virtual {v5, v4}, Ljava/lang/String;->equalsIgnoreCase(Ljava/lang/String;)Z

    move-result v5

    if-eqz v5, :h10_no_gzip

    new-instance v5, Ljava/util/zip/GZIPInputStream;

    invoke-direct {v5, v2}, Ljava/util/zip/GZIPInputStream;-><init>(Ljava/io/InputStream;)V

    move-object v2, v5

    :h10_no_gzip
    new-instance v0, Ljava/io/ByteArrayOutputStream;

    invoke-direct {v0}, Ljava/io/ByteArrayOutputStream;-><init>()V

    const/16 v5, 0x1000

    new-array v6, v5, [B

    :h10_read
    invoke-virtual {v2, v6}, Ljava/io/InputStream;->read([B)I

    move-result v3

    if-lez v3, :h10_read_done

    const/4 v4, 0x0

    invoke-virtual {v0, v6, v4, v3}, Ljava/io/ByteArrayOutputStream;->write([BII)V

    goto :h10_read

    :h10_read_done
    invoke-virtual {v2}, Ljava/io/InputStream;->close()V

    invoke-virtual {v1}, Ljava/net/HttpURLConnection;->disconnect()V

    const-string v3, "UTF-8"

    invoke-virtual {v0, v3}, Ljava/io/ByteArrayOutputStream;->toString(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v2

    invoke-virtual {v0}, Ljava/io/ByteArrayOutputStream;->close()V

"""
s = s[:start] + new_read + s[end:]

open(PATH, "w", encoding="utf-8").write(s)
print("h10: применён к", PATH)
PYEOF
