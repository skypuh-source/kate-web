#!/bin/sh
# патч f38 (Этап E.4 / push, 2026-10-16): регистрация устройства под «родным» app_id Kate
#
# Контекст: push получаем через FCM (свой проект Kate `gcm-kate-mobile`, sender 54740537194),
# а устройство в VK регистрируем вызовом account.registerDevice. На web-канале этот вызов
# уходит с web-токеном и инжектированным client_id=7879029 (веб-клиент), тогда как FCM-проект
# привязан к нативному приложению Kate (client_id=2685278). Есть риск, что VK доставляет push
# только для app_id, совпадающего с приложением FCM-проекта.
#
# Проверка на хосте (острый web-токен → web.api.vk.ru, реальный FCM-токен + device_id):
#   account.registerDevice (без app_id)                     -> {"response":1}
#   account.registerDevice &app_id=2685278                  -> {"response":1}
#   account.registerDevice &app_id=7879029                  -> {"response":1}
#   account.registerDevice?client_id=2685278                -> {"response":1}
#   account.registerDevice?client_id=2685278 &app_id=7879029-> {"response":1}
# VK принимает вызов при любых вариантах (app_id не валидируется). Данный патч выставляет
# app_id=2685278 (родной клиент Kate) — целевой маппинг на FCM-проект gcm-kate-mobile.
# Приёмка (факт доставки) — только живым входящим событием при погашенном экране.
#
# Фикс: в Api.registerDevice добавить параметр app_id=2685278 к Params.
# Регистры не расширяем: после put("push_provider","fcm") p1 и p2 свободны (метод .locals 1,
# p1/p2 — параметры, переиспользуются под результат sendRequest ниже).
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/api/Api.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

if 'const-string p2, "2685278"' in s:
    print("f38 Api: уже применён")
    sys.exit(0)

old = """    invoke-virtual {p4, p1, p2}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V

    .line 2821
    invoke-virtual {p0, p4}, Lcom/perm/kate/api/Api;->sendRequest(Lcom/perm/kate/api/Params;)Lorg/json/JSONObject;"""
new = """    invoke-virtual {p4, p1, p2}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V

    const-string p1, "app_id"

    const-string p2, "2685278"

    invoke-virtual {p4, p1, p2}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V

    .line 2821
    invoke-virtual {p0, p4}, Lcom/perm/kate/api/Api;->sendRequest(Lcom/perm/kate/api/Params;)Lorg/json/JSONObject;"""
assert s.count(old) == 1, "f38: якорь registerDevice не уникален/не найден"
s = s.replace(old, new, 1)

open(f, "w").write(s)
print("f38 Api.smali OK (registerDevice + app_id=2685278)")
EOF
