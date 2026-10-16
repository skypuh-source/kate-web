#!/bin/sh
# патч f36 (Этап F / багфикс, найден при UI-прогоне 2026-10-16):
# "no value for id" на стене группы.
#
# Проблема: VK на web-канале (web.api.vk.ru) подмешивает в ответ wall.get РЕКЛАМНЫЕ
# элементы прямо в массив "items": {"type":"ads", ...} — и у них НЕТ поля "id".
# Api.getWallMessages() прогоняет каждый item через WallMessage.parse(), а тот первым
# делом делает НЕохраняемый getLong("id") (WallMessage.smali:236) → org.json.JSONException:
# "No value for id". Исключение ловится в Session.execute, и в итоге стена остаётся пустой
# (WallFragment$2.error). Проявляется не всегда — реклама таргетируется.
#
# Подтверждено на живой выдаче wall.get (owner_id=-22844796, count=20): элементы бывают
# двух видов — ('post', есть id) x20 и ('ads', нет id) x3. wall.getById и wall.search
# рекламу НЕ подмешивают (no-id = 0), поэтому их циклы не трогаем.
#
# Фикс: пропускать элементы без "id" в циклах разбора стен:
#   1) Api.getWallMessages (wall.get)  — стена группы/пользователя (основной симптом);
#   2) Api.getWalls (execute+wall.get) — пакетная подкачка стен (UpdateService).
# Настоящий пост всегда имеет "id"; рекламные/служебные элементы — нет; пропуск безопасен.
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/api/Api.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

if "f36_skip" in s:
    print("f36 Api: уже применён")
    sys.exit(0)

# --- 1) getWallMessages (wall.get): пропуск items без "id" ----------------------
a1_old = """    check-cast v0, Lorg/json/JSONObject;

    .line 1265
    invoke-static {v0}, Lcom/perm/kate/api/WallMessage;->parse(Lorg/json/JSONObject;)Lcom/perm/kate/api/WallMessage;"""
a1_new = """    check-cast v0, Lorg/json/JSONObject;

    const-string v1, "id"

    invoke-virtual {v0, v1}, Lorg/json/JSONObject;->has(Ljava/lang/String;)Z

    move-result v1

    if-eqz v1, :f36_skip

    .line 1265
    invoke-static {v0}, Lcom/perm/kate/api/WallMessage;->parse(Lorg/json/JSONObject;)Lcom/perm/kate/api/WallMessage;"""
assert s.count(a1_old) == 1, "f36: якорь getWallMessages(parse) не уникален/не найден"
s = s.replace(a1_old, a1_new, 1)

a2_old = """    .line 1266
    iget-object v1, p3, Lcom/perm/kate/api/WallResponse;->items:Ljava/util/ArrayList;

    invoke-virtual {v1, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    add-int/lit8 p4, p4, 0x1"""
a2_new = """    .line 1266
    iget-object v1, p3, Lcom/perm/kate/api/WallResponse;->items:Ljava/util/ArrayList;

    invoke-virtual {v1, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    :f36_skip
    add-int/lit8 p4, p4, 0x1"""
assert s.count(a2_old) == 1, "f36: якорь getWallMessages(add) не уникален/не найден"
s = s.replace(a2_old, a2_new, 1)

# --- 2) getWalls (execute+wall.get): пропуск items без "id" ---------------------
a3_old = """    invoke-virtual {v1, v4}, Lorg/json/JSONArray;->getJSONObject(I)Lorg/json/JSONObject;

    move-result-object v5

    invoke-static {v5}, Lcom/perm/kate/api/WallMessage;->parse(Lorg/json/JSONObject;)Lcom/perm/kate/api/WallMessage;"""
a3_new = """    invoke-virtual {v1, v4}, Lorg/json/JSONArray;->getJSONObject(I)Lorg/json/JSONObject;

    move-result-object v5

    const-string v2, "id"

    invoke-virtual {v5, v2}, Lorg/json/JSONObject;->has(Ljava/lang/String;)Z

    move-result v2

    if-eqz v2, :f36_skip2

    invoke-static {v5}, Lcom/perm/kate/api/WallMessage;->parse(Lorg/json/JSONObject;)Lcom/perm/kate/api/WallMessage;"""
assert s.count(a3_old) == 1, "f36: якорь getWalls(parse) не уникален/не найден"
s = s.replace(a3_old, a3_new, 1)

a4_old = """    invoke-virtual {v3, v5}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    add-int/lit8 v4, v4, 0x1"""
a4_new = """    invoke-virtual {v3, v5}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z

    :f36_skip2
    add-int/lit8 v4, v4, 0x1"""
assert s.count(a4_old) == 1, "f36: якорь getWalls(add) не уникален/не найден"
s = s.replace(a4_old, a4_new, 1)

open(f, "w").write(s)
print("f36 Api.smali OK (пропуск items без id в getWallMessages и getWalls)")
EOF
