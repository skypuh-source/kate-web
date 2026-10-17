#!/bin/sh
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/api/Api.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()
if ':cond_skip_cid' in s:
    print("f39 уже применён")
    sys.exit(0)
old = """    :cond_keep
    const-string v4, "client_id"

    const-string v3, "7879029"

    invoke-virtual {p1, v4, v3}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V"""
if s.count(old) != 1:
    raise AssertionError('count!=1')
new = """    :cond_keep
    # f39
    iget-object v4, p1, Lcom/perm/kate/api/Params;->method_name:Ljava/lang/String;
    const-string v3, "account.registerDevice"
    invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v4
    if-eqz v4, :cond_force_cid
    const-string v4, "client_id"
    const-string v3, "2685278"
    invoke-virtual {p1, v4, v3}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V
    goto :cond_skip_cid
    :cond_force_cid
    const-string v4, "client_id"
    const-string v3, "7879029"
    invoke-virtual {p1, v4, v3}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V
    :cond_skip_cid"""
s2 = s.replace(old, new, 1)
open(f,'w').write(s2)
print('ok')
EOF
