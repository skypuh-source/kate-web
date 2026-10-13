#!/bin/sh
# патч f5: браузерный User-Agent для всех запросов (API + логин)
# корень Флуда: UA "KateMobileAndroid/133.11-..." триггерит антибот web.api.vk.ru
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/utils/UserAgent.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()
MARKER = 'Chrome/126.0.0.0'
if MARKER in s:
    print("f5: уже применён")
    sys.exit(0)
# Заменяем ВСЁ тело getUserAgent() целиком: от .locals до .end method.
# (старый якорный вариант оставлял недостижимый «хвост» исходного тела)
sig = '.method public static getUserAgent()Ljava/lang/String;'
assert sig in s, "f5: метод getUserAgent() не найден"
mstart = s.index(sig)
lstart = s.rfind('\n', mstart, s.index('.locals', mstart)) + 1
mend = s.index('.end method', mstart)
body = ('''    .locals 1

    const-string v0, "Mozilla/5.0 (Linux; Android 13; CPH2205) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"

    return-object v0
''')
s = s[:lstart] + body + s[mend:]
open(f, "w").write(s)
print("f5 UserAgent.smali OK")
EOF