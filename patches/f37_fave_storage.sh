#!/bin/sh
# патч f37 (Этап F / багфикс, найден при UI-прогоне 2026-10-16): "не работают закладки"
#
# Симптом: ПРОФИЛЬ -> Закладки -> вкладки ЛЮДИ/ГРУППЫ открываются пустыми с ошибкой (Toast):
#   com.perm.kate.api.KException: One of the parameters specified was missing or invalid:
#   target app id is required for official apps
#   at Api.getStorage(Api.java:5740) <- Session.getStorage <- FaveGroupsFragment.sync (и Users).
# Причина: на web-канале токен не несёт контекст приложения, и методы storage.get/storage.set
# требуют ЯВНЫЙ параметр app_id. Без него VK возвращает error 100 ("target app id is required
# for official apps"), исключение ловится в колбэке -> данные и локальная БД не читаются, список пуст.
#
# Проверено острым (web) токеном к web.api.vk.ru:
#   storage.get?key=kt_fv_gr                 -> error 100 (target app id is required)
#   storage.get?key=kt_fv_gr&app_id=7879029  -> {"response":[{"key":"kt_fv_gr","value":""}]}
#   storage.set?key=..&value=..&app_id=7879029 -> {"response":1}
# app_id = 7879029 (тот же, что client_id в Api.sendRequest и в мининге web_token).
#
# Фикс: добавить параметр app_id=7879029 в Params методов Api.getStorage и Api.setStorage.
# Регистры не расширяем: в getStorage после put("key") p1 свободен; в setStorage после put("value")
# свободны и p1, и p2 — переиспользуем их под ключ/значение app_id.
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/api/Api.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

if 'const-string p1, "app_id"\n\n    const-string v1, "7879029"' in s:
    print("f37 Api: уже применён")
    sys.exit(0)

# --- 1) getStorage: storage.get + app_id ---------------------------------------
g_old = """    .line 5739
    const-string v1, "key"

    invoke-virtual {v0, v1, p1}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V

    .line 5740
    invoke-virtual {p0, v0}, Lcom/perm/kate/api/Api;->sendRequest(Lcom/perm/kate/api/Params;)Lorg/json/JSONObject;"""
g_new = """    .line 5739
    const-string v1, "key"

    invoke-virtual {v0, v1, p1}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V

    const-string p1, "app_id"

    const-string v1, "7879029"

    invoke-virtual {v0, p1, v1}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V

    .line 5740
    invoke-virtual {p0, v0}, Lcom/perm/kate/api/Api;->sendRequest(Lcom/perm/kate/api/Params;)Lorg/json/JSONObject;"""
assert s.count(g_old) == 1, "f37: якорь getStorage не уникален/не найден"
s = s.replace(g_old, g_new, 1)

# --- 2) setStorage: storage.set + app_id ---------------------------------------
s_old = """    .line 5732
    const-string p1, "value"

    invoke-virtual {v0, p1, p2}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V

    .line 5733
    invoke-virtual {p0, v0}, Lcom/perm/kate/api/Api;->sendRequest(Lcom/perm/kate/api/Params;)Lorg/json/JSONObject;"""
s_new = """    .line 5732
    const-string p1, "value"

    invoke-virtual {v0, p1, p2}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V

    const-string p1, "app_id"

    const-string v1, "7879029"

    invoke-virtual {v0, p1, v1}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V

    .line 5733
    invoke-virtual {p0, v0}, Lcom/perm/kate/api/Api;->sendRequest(Lcom/perm/kate/api/Params;)Lorg/json/JSONObject;"""
assert s.count(s_old) == 1, "f37: якорь setStorage не уникален/не найден"
s = s.replace(s_old, s_new, 1)

open(f, "w").write(s)
print("f37 Api.smali OK (storage.get/set + app_id=7879029)")
EOF
