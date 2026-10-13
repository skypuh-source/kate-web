#!/bin/sh
# патч f2: web-канал в Api.smali (инъекция токена+client_id, хост, v=5.289)
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/api/Api.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

block = """    invoke-static {}, Lcom/perm/kate/api/WebChannel;->throttle()V

    invoke-static {}, Lcom/perm/kate/api/WebChannel;->getToken()Ljava/lang/String;

    move-result-object v3

    if-eqz v3, :cond_keep

    invoke-virtual {v3}, Ljava/lang/String;->length()I

    move-result v4

    if-lez v4, :cond_keep

    iput-object v3, p0, Lcom/perm/kate/api/Api;->access_token:Ljava/lang/String;

    const-string v4, "access_token"

    invoke-virtual {p1, v4, v3}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V

    :cond_keep
    const-string v4, "client_id"

    const-string v3, "7879029"

    invoke-virtual {p1, v4, v3}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V
"""

anchor = """    .line 128
    invoke-static {}, Ljava/util/Calendar;->getInstance()Ljava/util/Calendar;"""
assert anchor in s, "anchor sendRequest не найден"
assert "WebChannel" not in s, "патч уже применён"
s = s.replace(anchor, block.strip("\n") + "\n" + anchor, 1)

old_host = 'const-string v1, "https://api.vk.ru/method/"'
new_host = 'const-string v1, "https://web.api.vk.ru/method/"'
assert s.count(old_host) == 1, "хост не найден"
s = s.replace(old_host, new_host, 1)

# отключить искусственный дневной лимит API этого APK (10 вызовов/сутки, зашит в com.perm.kate.api)
lim_old = ".field public static API_DAY_LIMIT:I = 0xa"
lim_new = ".field public static API_DAY_LIMIT:I = 0x7fffffff"
assert lim_old in s, "API_DAY_LIMIT не найден"
s = s.replace(lim_old, lim_new, 1)

for old, new in [
    ('const-string p2, "5.243"', 'const-string p2, "5.289"'),
    ('const-string p3, "5.243"', 'const-string p3, "5.289"'),
    ('const-string p2, "5.215"', 'const-string p2, "5.289"'),
    ('const-string p2, "5.235"', 'const-string p2, "5.289"'),
    ('const-string p2, "5.212"', 'const-string p2, "5.289"'),
    ('const-string v1, "5.211"', 'const-string v1, "5.289"'),
]:
    n = s.count(old)
    assert n >= 1, "v-константа не найдена: " + old
    if n > 1:
        print("WARN: %s встречается %dx" % (old, n))
    s = s.replace(old, new)

open(f, "w").write(s)
print("f2 Api.smali OK")
EOF