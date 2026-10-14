#!/bin/sh
# патч f4: мета (targetSdk 36->29; debuggable для отладки/run-as).
# При target>=30 установка падает: "Targeting R+ (version 30 and above) requires the
# resources.arsc of installed APKs to be stored uncompressed and aligned on a 4-byte
# boundary" — apktool кладёт resources.arsc сжатым. Поэтому target держим на 29.
# Следствие: на Android 13 к медиа применяется легаси-модель (см. f11).
K="$(dirname "$0")/../"
cd "$K" || exit 1

# apktool.yml
Y=decode/apktool.yml
python3 - "$Y" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()
old = "  targetSdkVersion: 36"
new = "  targetSdkVersion: 29"
assert s.count(old) == 1, "targetSdk не найден"
assert "targetSdkVersion: 29" not in s.replace(old, "", 1) or s.count("targetSdkVersion") == 1, "патч уже применён"
s = s.replace(old, new, 1)
open(f, "w").write(s)
print("apktool.yml OK")
EOF

# AndroidManifest.xml
M=decode/AndroidManifest.xml
python3 - "$M" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()
old = '<application android:allowBackup="false"'
new = '<application android:debuggable="true" android:allowBackup="false"'
assert s.count(old) == 1, "application тег не найден"
assert 'android:debuggable="true"' not in s, "патч уже применён"
s = s.replace(old, new, 1)
open(f, "w").write(s)
print("AndroidManifest.xml OK")
EOF