#!/bin/sh
# патч f3: longpoll version 10 -> 3 (опрос как у m.vk.ru)
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/LongPoll\$PollThread.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()
assert 'const-wide/16 v10, 0xa' in s, "литерал version не найден"
assert 'const-wide/16 v10, 0x3' not in s, "патч уже применён"
s = s.replace('const-wide/16 v10, 0xa', 'const-wide/16 v10, 0x3', 1)
open(f, "w").write(s)
print("f3 LongPoll OK")
EOF