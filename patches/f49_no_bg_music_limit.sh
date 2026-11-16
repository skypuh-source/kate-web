#!/bin/sh
# патч f49 (2026-10-29): снимаем лимит фонового прослушивания музыки.
#
# Kate ограничивает прослушивание в фоне 30 минутами (preference "bgml",
# значение по умолчанию 0x708 = 1800 секунд). Ограничение реализовано в двух
# независимых местах, поэтому одного изменения недостаточно:
#
#   1) BackgroundMusicCounter.isLimit() — сравнивает счётчик с getLimit() и
#      используется в Player, PlayerExo, PlaybackService (8 вызовов) и в
#      BaseActivity, где по нему показывается диалог о лимите;
#   2) BackgroundMusicCounter.startTimer() — планирует postDelayed на
#      (limit - counter) секунд, а BackgroundMusicCounter$1.run() безусловно
#      вызывает pause() и toast(), то есть останавливает музыку даже если
#      isLimit() уже всегда false.
#
# Дополнительно поднимаем порог в stopCounter(): после 7200 секунд фонового
# прослушивания он отправляет reportError("bg play too long") и выходит, не
# обновив счётчик и не остановив таймер. Пока лимит был 30 минут, эта ветка
# почти не срабатывала; без лимита двухчасовые сессии станут обычным делом.
#
# Что не меняем:
#   • getLimit()/setLimit() и preference "bgml" — остаются для совместимости
#     с настройками и логами;
#   • toast()/pause() — нужны другим сценариям (пауза при звонке и т.п.).
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
MARK = "f49_no_bg_music_limit"
PATH = "decode/smali/com/perm/utils/BackgroundMusicCounter.smali"


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, s):
    with open(path, "w", encoding="utf-8") as f:
        f.write(s)


def replace_method(s, signature, body):
    """Заменяет тело метода целиком, сохраняя отступы и переводы строк."""
    assert s.count(signature) == 1, "f49: сигнатура %r не найдена/не уникальна" % signature
    start = s.index(signature)
    end = s.index(".end method", start) + len(".end method")
    return s[:start] + body + s[end:]


s = read(PATH)

# --- 1) isLimit(): всегда false ------------------------------------------------
if MARK + ": isLimit" in s:
    print("f49 isLimit: уже применён")
else:
    s = replace_method(
        s,
        ".method public static isLimit()Z",
        """.method public static isLimit()Z
    .locals 1

    # f49_no_bg_music_limit: isLimit
    const/4 v0, 0x0

    return v0
.end method""",
    )
    print("f49 isLimit: лимит отключён")

# --- 2) startTimer(): не планировать остановку по лимиту ------------------------
if MARK + ": startTimer" in s:
    print("f49 startTimer: уже применён")
else:
    s = replace_method(
        s,
        ".method public static startTimer()V",
        """.method public static startTimer()V
    .locals 0

    # f49_no_bg_music_limit: startTimer
    # Остановка по лимиту не планируется: музыка играет в фоне без ограничения.
    return-void
.end method""",
    )
    print("f49 startTimer: таймер лимита не запускается")

# --- 3) stopCounter(): порог "слишком долго" 2 часа -> недостижимый ------------
if MARK + ": stopCounter" in s:
    print("f49 stopCounter: уже применён")
else:
    old = "const-wide/16 v4, 0x1c20"
    new = ("# f49_no_bg_music_limit: stopCounter\n"
           "    const-wide/32 v4, 0x7fffffff")
    assert s.count(old) == 1, "f49: якорь порога stopCounter не найден/не уникален"
    s = s.replace(old, new, 1)
    print("f49 stopCounter: порог 7200 с поднят")

write(PATH, s)
PYEOF
