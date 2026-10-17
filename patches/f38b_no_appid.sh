#!/bin/sh
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/api/Api.smali
python3 - "$F" <<'PY'
import sys
f=sys.argv[1]
s=open(f).read()
# remove app_id block we added
block='''    const-string p1, "app_id"

    const-string p2, "2685278"

    invoke-virtual {p4, p1, p2}, Lcom/perm/kate/api/Params;->put(Ljava/lang/String;Ljava/lang/String;)V
'''
if block not in s:
    print('already absent or different')
    sys.exit(0)
s2=s.replace(block,'')
open(f,'w').write(s2)
print('ok')
PY
