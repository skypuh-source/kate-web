#!/bin/sh
# патч f48 (2026-10-27): скрытая служба-якорь по умолчанию и суточная
# автоматическая проверка обновлений.
#
# 1) «Скрыть службу-якорь» теперь включено по умолчанию:
#    - android:defaultValue="true" в обоих вариантах preferences.xml;
#    - KeepAliveService читает key_hide_keepalive с default=true.
#    Пользователь по-прежнему может выключить скрытие в настройках.
#
# 2) Автопроверка обновлений при запуске выполняется не чаще раза в сутки.
#    UpdateChecker.checkSometimes уже вызывается из MainActivity через 4 секунды
#    после старта и хранит last_update_check; меняем интервал с 48 часов
#    (0xa4cb800) на 24 часа (0x5265c00). Ручная проверка из настроек не
#    ограничивается этим интервалом.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'EOF'
import os

MARK = "f48_keepalive_default"

# --- 1) значения по умолчанию в настройках -----------------------------------
for p in ("decode/res/xml/preferences.xml", "decode/res/xml-v22/preferences.xml"):
    if not os.path.exists(p):
        continue
    s = open(p, encoding="utf-8").read()
    if 'android:key="key_hide_keepalive"' not in s:
        raise SystemExit("f48: в %s нет key_hide_keepalive — сначала примените f44" % p)
    lines = s.splitlines(True)
    changed = False
    for i, line in enumerate(lines):
        if 'android:key="key_hide_keepalive"' in line and 'android:defaultValue="false"' in line:
            lines[i] = line.replace('android:defaultValue="false"', 'android:defaultValue="true"', 1)
            changed = True
    if not changed:
        print("f48: %s — уже применён" % p)
    else:
        open(p, "w", encoding="utf-8").write("".join(lines))
        print("f48: %s — скрытие по умолчанию включено" % p)

# --- 2) KeepAliveService: default=true ---------------------------------------
p = "decode/smali/com/perm/kate/KeepAliveService.smali"
s = open(p, encoding="utf-8").read()
old = '''    const-string v1, "key_hide_keepalive"

    const/4 v2, 0x0

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getBoolean(Ljava/lang/String;Z)Z'''
new = '''    const-string v1, "key_hide_keepalive"

    const/4 v2, 0x1

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getBoolean(Ljava/lang/String;Z)Z'''
if old in s:
    assert s.count(old) == 1, "f48: якорь getBoolean не уникален"
    s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8").write(s)
    print("f48: KeepAliveService — скрытие по умолчанию включено")
else:
    print("f48: KeepAliveService — уже применён")

# --- 3) UpdateChecker: раз в сутки вместо двух --------------------------------
p = "decode/smali/com/perm/utils/UpdateChecker.smali"
s = open(p, encoding="utf-8").read()
old = "    const-wide/32 v6, 0xa4cb800"
new = "    const-wide/32 v6, 0x5265c00"
if old in s:
    assert s.count(old) == 1, "f48: якорь интервала 48ч не уникален"
    s = s.replace(old, new, 1)
    open(p, "w", encoding="utf-8").write(s)
    print("f48: UpdateChecker — интервал 24 часа")
else:
    print("f48: UpdateChecker — уже применён")
EOF
