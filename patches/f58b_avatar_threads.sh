#!/bin/sh
# патч f58b (2026-11-18): ускоряем загрузку аватарок в списке диалогов.
#
# ImageLoader.queuePhoto создаёт пул из 5 потоков с приоритетом 4 (ниже
# обычного). Для списка диалогов, где видимы десятки аватарок сразу, этого мало.
#
# Фикс: 6 потоков, приоритет 5. Сеть и декод остаются те же, меняется только
# параллелизм; риск для остальных экранов минимален.
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/ImageLoader.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

old_threads = '''    :goto_2
    const/4 v0, 0x5

    if-ge p1, v0, :cond_2'''
new_threads = '''    :goto_2
    const/4 v0, 0x6

    if-ge p1, v0, :cond_2'''

if old_threads in s:
    assert s.count(old_threads) == 1, "f58b: пул потоков не уникален"
    s = s.replace(old_threads, new_threads, 1)
    print("f58b ImageLoader: 5 -> 6 потоков")
elif new_threads in s:
    print("f58b ImageLoader: потоков уже 6")
else:
    raise SystemExit("f58b: якорь пула потоков не найден")

old_prio = '''    const/4 v1, 0x4

    .line 249
    invoke-virtual {v0, v1}, Ljava/lang/Thread;->setPriority(I)V'''
new_prio = '''    const/4 v1, 0x5

    .line 249
    invoke-virtual {v0, v1}, Ljava/lang/Thread;->setPriority(I)V'''

if old_prio in s:
    assert s.count(old_prio) == 1, "f58b: приоритет не уникален"
    s = s.replace(old_prio, new_prio, 1)
    print("f58b ImageLoader: приоритет 4 -> 5")
elif new_prio in s:
    print("f58b ImageLoader: приоритет уже 5")
else:
    raise SystemExit("f58b: якорь приоритета не найден")

open(f, "w").write(s)
EOF
