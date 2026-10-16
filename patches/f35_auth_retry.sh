#!/bin/sh
# патч f35 (этап E.3, жизненный цикл сессии): авто-пере-минт web_token при "unauthorized".
#
# Проблема: на web-канале КАЖДЫЙ запрос несёт web_token из WebChannel.getToken().
# Если токен истёк/отозван (или mint временно не дал токен, и Api отправил исходный
# OAuth-токен Кати), VK отвечает error_code 5 (User authorization failed).
# Сейчас Session.execute (Session.smali:3117, :cond_d/:goto_4 — коды 4 и 5) только
# инкрементит invalid_token_counter и после порога показывает LoginNotification
# (ручной повторный вход). Авто-восстановления нет; WebChannel.refresh() не вызывается.
#
# Фикс: на ПЕРВОЙ ошибке 5 (error_code==5 и recursion_count<=1) форсируем
# WebChannel.refresh() (WebMint пере-минтит токен) и ОДИН раз повторяем команду
# (execute(command)). Повтор ограничен recursion_count (лимит рекурсии 10) и тем, что
# на повторе recursion_count станет 2 → дальнейшие ошибки 5 идут штатным путём.
# Ветка «куки отозваны, mint не даёт токен» остаётся штатной: счётчик + LoginNotification.
#
# Аналог: существующая ветка error 6 (Session.smali ~2911) уже повторяет execute() после sleep.
K="$(dirname "$0")/../"
cd "$K" || exit 1
F=decode/smali/com/perm/kate/session/Session.smali
python3 - "$F" <<'EOF'
import sys
f = sys.argv[1]
s = open(f).read()

anchor = """    :cond_d
    :goto_4
    iget v2, p0, Lcom/perm/kate/session/Session;->invalid_token_counter:I
"""
inserted = """    :cond_d
    :goto_4
    iget v2, v1, Lcom/perm/kate/api/KException;->error_code:I

    const/4 v3, 0x5

    if-ne v2, v3, :cond_d_orig

    iget v2, p1, Lcom/perm/kate/session/Command;->recursion_count:I

    const/4 v3, 0x1

    if-le v2, v3, :cond_d_retry

    goto :cond_d_orig

    :cond_d_retry
    invoke-static {}, Lcom/perm/kate/api/WebChannel;->refresh()Ljava/lang/String;

    invoke-virtual {p0, p1}, Lcom/perm/kate/session/Session;->execute(Lcom/perm/kate/session/Command;)V

    goto/16 :goto_5

    :cond_d_orig
    iget v2, p0, Lcom/perm/kate/session/Session;->invalid_token_counter:I
"""

if ':cond_d_orig' in s:
    print("f35 Session.smali: уже применён")
    sys.exit(0)

assert s.count(anchor) == 1, "f35: якорь :cond_d/:goto_4 не найден или не уникален (%d)" % s.count(anchor)
s = s.replace(anchor, inserted, 1)
open(f, "w").write(s)
print("f35 Session.smali OK (error 5 -> refresh + 1 retry)")
EOF
