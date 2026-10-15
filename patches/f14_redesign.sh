#!/bin/sh
# патч f14: Ответы через notifications.getRedesign + конвертер RedesignNotifications
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/api/Api.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

start = ".method public getNotifications(Ljava/lang/String;Ljava/lang/Long;Ljava/lang/Long;Ljava/lang/Integer;Ljava/lang/String;)Lcom/perm/kate/api/Notifications;"
assert start in s, "getNotifications не найден"
assert "notifications.getRedesign" not in s, "патч f14 уже применён"

i = s.index(start)
j = s.index("\n.end method\n", i) + len("\n.end method\n")
old = s[i:j]

new = """.method public getNotifications(Ljava/lang/String;Ljava/lang/Long;Ljava/lang/Long;Ljava/lang/Integer;Ljava/lang/String;)Lcom/perm/kate/api/Notifications;
    .locals 2

    .line 2835
    new-instance v0, Lcom/perm/kate/api/Params;

    const-string v1, "notifications.getRedesign"

    invoke-direct {v0, v1}, Lcom/perm/kate/api/Params;-><init>(Ljava/lang/String;)V

    .line 2839
    const-string v1, "count"

    invoke-virtual {v0, v1, p4}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/Integer;)V

    .line 2840
    const-string v1, "start_from"

    invoke-virtual {v0, v1, p5}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V

    .line 2841
    invoke-virtual {p0, v0}, Lcom/perm/kate/api/Api;->sendRequest(Lcom/perm/kate/api/Params;)Lorg/json/JSONObject;

    move-result-object p1

    .line 2842
    const-string p2, "response"

    invoke-virtual {p1, p2}, Lorg/json/JSONObject;->optJSONObject(Ljava/lang/String;)Lorg/json/JSONObject;

    move-result-object p1

    .line 2843
    invoke-static {p1}, Lcom/perm/kate/api/RedesignNotifications;->convert(Lorg/json/JSONObject;)Lcom/perm/kate/api/Notifications;

    move-result-object p1

    return-object p1
.end method
"""

s = s[:i] + new + s[j:]
open(f, "w").write(s)
print("f14 Api.getNotifications -> getRedesign OK")
EOF
