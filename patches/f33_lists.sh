#!/bin/sh
# патч f33 (производительность/ускорение, Этап P5): кэш пользователей в списке друзей.
#
# Проблема: FriendsListAdapter.getView() на КАЖДУЮ привязку строки вызывает
# DataHelper.fetchUser(J), а это реальный SQL-запрос к таблице users ("_id=?").
# При скролле большого списка друзей/подписчиков это десятки SQL-запросов в секунду
# на UI-потоке.
#
# Фикс: использовать штатный кэширующий слой com/perm/utils/UserCache (он уже
# применяется в AlbumCommentsAdapter, CommentListAdapter, AttachmentsHelper,
# NewsCursorAdapter и др.). UserCache.get(J) сначала смотрит HashMap, и только при
# промахе идёт в БД (fetchUser) и кладёт результат в кэш.
#
# Безопасность: семантика результата та же (при промахе — тот же fetchUser); меняется
# лишь наличие кэша. Известный компромисс: в пределах жизни адаптера объект User
# (в т.ч. флаг online) не перечитывается — как и в остальных адаптерах приложения.
# Адаптер создаётся заново при открытии экрана друзей, так что online обновляется
# при пересоздании списка.
#
# У FriendsListAdapter ТРИ независимых конструктора (без делегирования) — поле
# userCache инициализируется во всех трёх.
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/FriendsListAdapter.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

if "FriendsListAdapter;->userCache" in s:
    print("f33 FriendsListAdapter: уже применён")
    sys.exit(0)

# 1) объявление поля
old_field = """.field public final users:Ljava/util/ArrayList;


# direct methods
"""
new_field = """.field public final users:Ljava/util/ArrayList;

.field public final userCache:Lcom/perm/utils/UserCache;


# direct methods
"""
assert s.count(old_field) == 1, "f33: якорь поля users не найден/не уникален"
s = s.replace(old_field, new_field, 1)

# 2) инициализация во всех конструкторах (после присвоения users)
block = ("\n\n    new-instance v0, Lcom/perm/utils/UserCache;"
         "\n\n    invoke-direct {v0}, Lcom/perm/utils/UserCache;-><init>()V"
         "\n\n    iput-object v0, p0, Lcom/perm/kate/FriendsListAdapter;->userCache:Lcom/perm/utils/UserCache;")

line_v0 = "    iput-object v0, p0, Lcom/perm/kate/FriendsListAdapter;->users:Ljava/util/ArrayList;"
line_p1 = "    iput-object p1, p0, Lcom/perm/kate/FriendsListAdapter;->users:Ljava/util/ArrayList;"
assert s.count(line_v0) == 2, "f33: якорь users(v0) ожидался 2 раза, есть %d" % s.count(line_v0)
assert s.count(line_p1) == 1, "f33: якорь users(p1) ожидался 1 раз, есть %d" % s.count(line_p1)
s = s.replace(line_v0, line_v0 + block)
s = s.replace(line_p1, line_p1 + block)

# 3) источник: DataHelper.db -> userCache
old_src = "    sget-object p3, Lcom/perm/kate/KApplication;->db:Lcom/perm/kate/db/DataHelper;"
new_src = "    iget-object p3, p0, Lcom/perm/kate/FriendsListAdapter;->userCache:Lcom/perm/utils/UserCache;"
assert s.count(old_src) == 1, "f33: якорь sget-object db не уникален/не найден"
s = s.replace(old_src, new_src, 1)

# 4) вызов: fetchUser -> userCache.get
old_call = "    invoke-virtual {p3, v1, v2}, Lcom/perm/kate/db/DataHelper;->fetchUser(J)Lcom/perm/kate/api/User;"
new_call = "    invoke-virtual {p3, v1, v2}, Lcom/perm/utils/UserCache;->get(J)Lcom/perm/kate/api/User;"
assert s.count(old_call) == 1, "f33: якорь fetchUser не уникален/не найден"
s = s.replace(old_call, new_call, 1)

open(f, "w").write(s)
print("f33 FriendsListAdapter.smali OK (fetchUser -> userCache.get, кэш во всех 3 конструкторах)")
EOF
