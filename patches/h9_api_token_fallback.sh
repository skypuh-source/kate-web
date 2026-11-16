#!/bin/sh
# h9_api_token_fallback.sh — резервный access_token из Account (этап H).
#
# Проблема: Api.sendRequest() берёт токен из WebChannel.getToken(). Если тот
# вернул null или пустую строку (WebMint/cookies не сработали), access_token
# вообще не добавляется в Params, хотя в Api.access_token лежит валидный токен
# из Account (Session создаёт Api(account.access_token, ...)).
#
# VK на запрос без токена отвечает error 5:
#   "User authorization failed: client_secret is incorrect."
# Из-за этого messages.getLongPollServer падает каждые ~2 минуты, LongPoll
# не стартует, а Session считает это сбоем авторизации.
#
# Решение: если WebChannel.getToken() пуст, использовать Api.access_token.
# Если и он пуст — оставить прежнее поведение (запрос без токена).
#
# Важно: if-eqz в smali — «ветка, если == 0». Раньше здесь стоял if-nez, и при
# НЕПУСТОМ web-токене управление уходило в фолбэк, то есть все запросы шли
# токеном аккаунта (VK ID), который VK режет Flood control. Теперь наоборот:
# фолбэк только для пустого web-токена.
#
# Не входит в цепочку f*: запускается вручную.
#   sh patches/h9_api_token_fallback.sh
# Идемпотентен: повторный запуск ничего не дублирует.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
MARK = "# h9_api_token_fallback"
PATH = "decode/smali/com/perm/kate/api/Api.smali"

s = open(PATH, encoding="utf-8").read()
if MARK in s:
    print("h9: уже применён")
    raise SystemExit(0)

anchor = """    move-result-object v3

    if-eqz v3, :cond_keep

    invoke-virtual {v3}, Ljava/lang/String;->length()I

    move-result v4

    if-lez v4, :cond_keep

    iput-object v3, p0, Lcom/perm/kate/api/Api;->access_token:Ljava/lang/String;
"""

block = """    move-result-object v3

    # h9_api_token_fallback: пустой WebChannel-токен → берём токен из Account
    if-eqz v3, :h9_token_fallback

    invoke-virtual {v3}, Ljava/lang/String;->length()I

    move-result v4

    if-eqz v4, :h9_token_fallback

    goto :h9_token_ready

    :h9_token_fallback
    iget-object v3, p0, Lcom/perm/kate/api/Api;->access_token:Ljava/lang/String;

    :h9_token_ready
    if-eqz v3, :cond_keep

    invoke-virtual {v3}, Ljava/lang/String;->length()I

    move-result v4

    if-lez v4, :cond_keep

    iput-object v3, p0, Lcom/perm/kate/api/Api;->access_token:Ljava/lang/String;
"""

if s.count(anchor) != 1:
    raise SystemExit("h9: якорь не найден/не уникален (%d)" % s.count(anchor))

s = s.replace(anchor, block, 1)
open(PATH, "w", encoding="utf-8").write(s)
print("h9: применён к", PATH)
PYEOF
