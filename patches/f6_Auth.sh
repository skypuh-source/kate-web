#!/bin/sh
# патч f6: убрать Authorization: Bearer <token> в sendRequestInternal
# причина флуда web.api.vk.ru: web-токен передаётся и заголовком, и параметром (бот-триггер)
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/api/Api.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()
block = '''    .line 263
    const-string v6, "Authorization"

    new-instance v7, Ljava/lang/StringBuilder;

    invoke-direct {v7, v4}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    iget-object v4, p0, Lcom/perm/kate/api/Api;->access_token:Ljava/lang/String;

    invoke-virtual {v7, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v7}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v4

    invoke-virtual {v5, v6, v4}, Ljava/net/URLConnection;->setRequestProperty(Ljava/lang/String;Ljava/lang/String;)V

    if-eqz p3, :cond_2
'''
if block not in s:
    print("f6: Authorization уже удалён")
    sys.exit(0)
assert s.count(block) == 1, "f6: блока Authorization больше одной копии"
s = s.replace(block, "    if-eqz p3, :cond_2\n", 1)
open(f, "w").write(s)
print("f6 Api.smali OK (Authorization удалён)")
EOF