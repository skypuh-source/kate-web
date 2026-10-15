#!/bin/sh
# патч f31 (производительность/ускорение): сеть — keep-alive + мягче троттл.
#
# P2: в успешной ветке Api.sendRequestInternal вызывался HttpURLConnection.disconnect()
#     (перед return-object p1, ВНЕ try). disconnect() закрывает сокет, убирая соединение из
#     keep-alive пула -> каждый запрос заново проходит TCP+TLS-хендшейк. Тело уже вычитано
#     полностью (convertStreamToString), поэтому без disconnect() соединение переиспользуется.
#     В ветке ошибки (finally, <.catchall>) disconnect оставляем.
# P3: глобальный WebChannel.throttle() держал паузу >=500 мс между ЛЮБЫМИ запросами (общий лок),
#     из-за чего всплеск (лента+счётчики+диалоги) сериализовался. Интервал 0x1f4(500)->0xfa(250).
K="$(dirname "$0")/../"
cd "$K" || exit 1

# --- P2: Api.smali — убрать disconnect() в успешной ветке ---
python3 - decode/smali/com/perm/kate/api/Api.smali <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

old = """    .line 295
    invoke-virtual {v5}, Ljava/net/HttpURLConnection;->disconnect()V

    return-object p1"""
new = """    .line 295
    return-object p1"""

if new in s and old not in s:
    print("f31 Api.smali: уже применён")
    sys.exit(0)
assert old in s, "f31: якорь disconnect+return не найден"
assert s.count(old) == 1, "f31: якорь disconnect+return не уникален"
s = s.replace(old, new, 1)
open(f, "w").write(s)
print("f31 Api.smali OK (keep-alive: успешный disconnect убран)")
EOF
[ $? -eq 0 ] || exit 1

# --- P3: WebChannel.smali — троттл 500 -> 250 мс ---
python3 - decode/smali/com/perm/kate/api/WebChannel.smali <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

old = "    const-wide/16 v4, 0x1f4"
new = "    const-wide/16 v4, 0xfa"

if s.count(old) == 0 and s.count(new) >= 1:
    print("f31 WebChannel.smali: уже применён")
    sys.exit(0)
assert s.count(old) == 1, "f31: якорь throttle 0x1f4 не уникален (%d)" % s.count(old)
s = s.replace(old, new, 1)
open(f, "w").write(s)
print("f31 WebChannel.smali OK (throttle 500->250 ms)")
EOF
