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
old = '''    .locals 7

    .line 26
    :try_start_0
    invoke-static {}, Ljava/util/Locale;->getDefault()Ljava/util/Locale;

    move-result-object v0

    invoke-virtual {v0}, Ljava/util/Locale;->getLanguage()Ljava/lang/String;

    move-result-object v0

    .line 27
    const-string v1, "KateMobileAndroid/%s-%d (Android %s; SDK %d; %s; %s %s; %s)"
'''
assert old in s, "f5: не найдена шапка getUserAgent()"
s = s.replace(old, '''    .locals 1

    const-string v0, "Mozilla/5.0 (Linux; Android 13; CPH2205) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"

    return-object v0
''', 1)
# оставшийся хвост старого тела (format/catchall) удаляем до .end method метода getUserAgent
i = s.find('''    .line 27
    invoke-static {v1, v4}, Ljava/lang/String;->format''')
assert i != -1, "f5: хвост getUserAgent() не найден"
j = s.find('.end method', i)
s = s[:i] + s[j:]
open(f, "w").write(s)
print("f5 UserAgent.smali OK")
EOF