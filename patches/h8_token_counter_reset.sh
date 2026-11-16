#!/bin/sh
# h8_token_counter_reset.sh — сброс счётчика ошибок токена (этап H).
#
# Проблема: Session.invalid_token_counter только увеличивается при error 5
# и нигде не сбрасывается. Достаточно двух сбоев за всё время работы
# процесса (даже с промежутком в дни), чтобы показать LoginNotification.
#
# Решение: при успешном выполнении команды (reportSuccess) сбрасывать
# счётчик в 0. Это не скрывает повторяющуюся проблему: если токен реально
# перестал работать, error 5 повторится и счётчик снова вырастет.
#
# Не входит в цепочку f*: запускается вручную.
#   sh patches/h8_token_counter_reset.sh
# Идемпотентен: повторный запуск ничего не дублирует.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
MARK = "# h8_token_counter_reset"
PATH = "decode/smali/com/perm/kate/session/Session.smali"

s = open(PATH, encoding="utf-8").read()
if MARK in s:
    print("h8: уже применён")
    raise SystemExit(0)

anchor = """    .line 197
    iget-object v0, p1, Lcom/perm/kate/session/Command;->res:Ljava/lang/Object;

    invoke-virtual {p1, v0}, Lcom/perm/kate/session/Command;->reportSuccess(Ljava/lang/Object;)V

    return-void
"""

block = """    .line 197
    iget-object v0, p1, Lcom/perm/kate/session/Command;->res:Ljava/lang/Object;

    invoke-virtual {p1, v0}, Lcom/perm/kate/session/Command;->reportSuccess(Ljava/lang/Object;)V

    # h8_token_counter_reset: успешная команда — сбрасываем счётчик error 5
    const/4 v1, 0x0

    iput v1, p0, Lcom/perm/kate/session/Session;->invalid_token_counter:I

    return-void
"""

if s.count(anchor) != 1:
    raise SystemExit("h8: якорь не найден/не уникален (%d)" % s.count(anchor))

s = s.replace(anchor, block, 1)
open(PATH, "w", encoding="utf-8").write(s)
print("h8: применён к", PATH)
PYEOF
