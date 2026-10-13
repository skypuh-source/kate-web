#!/bin/sh
# патч f8: полный список диалогов при дефолтной настройке Online.
# Дефолт "Online only when sending messages" (key_online="2") -> Online.isEnabled()==false,
# из-за чего главный список (group_id==0) грузился через offlineRefresh (messages.search q=* count=10)
# и был обрезан. Заставляем главный список идти полной онлайн-загрузкой refreshInThread()
# (messages.getConversations count=30), не меняя семантику онлайн-статуса.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'EOF'
f = "decode/smali/com/perm/kate/MessagesFragment.smali"
s = open(f).read()
old = """    .line 225
    :cond_3
    invoke-virtual {p0}, Lcom/perm/kate/MessagesFragment;->offlineRefreshInThread()V"""
new = """    .line 225
    :cond_3
    invoke-virtual {p0}, Lcom/perm/kate/MessagesFragment;->refreshInThread()V"""
if new in s:
    print("f8: уже пропатчен")
else:
    assert old in s, "f8: якорь offlineRefreshInThread в MessagesFragment не найден"
    s = s.replace(old, new, 1)
    open(f, "w").write(s)
    print("f8: главный список диалогов -> refreshInThread")
EOF
