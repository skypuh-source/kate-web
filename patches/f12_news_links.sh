#!/bin/sh
# патч f12: внешние ссылки в постах (лента) не открываются.
#
# Две независимые причины:
#
# (A) Разметка alias нового формата. web.api.vk.ru (v=5.289) отдаёт ссылки в постах как
#       [#alias|DISPLAY|URL]        (адрес В КОНЦЕ)
#     а парсер Kate (NewsCursorAdapter.spannableLink, pattern
#       \[([^\]\[]*?)(:bp-\d*_\d*)?\|(.*?)\] ) ожидает СТАРЫЙ формат
#       [URL|DISPLAY]               (адрес В НАЧАЛЕ).
#     Из-за этого "#alias" принимается за адрес, "DISPLAY|URL" — за текст: в посте
#     показывается мусор, а клик ведёт в несуществующий https://vk.com/#alias.
#     Фикс: нормализуем тело ответа API в единственной точке (Api.sendRequestInternal),
#     переписывая [#alias|DISPLAY|URL] -> [URL|DISPLAY]. Работает везде (лента, стена,
#     комментарии, сообщения).
#
# (B) Обработчик клика в ленте умеет только VK-ссылки. NewsCursorAdapter$3.onClick
#     (спан ссылки из spannableLink) вызывает только Helper.openVK_COMlink(...), который
#     для внешних URL возвращает false и НИЧЕГО не делает (в отличие от сообщений, где
#     используется Helper.openUrl с фолбэком в браузер). Фикс: заменить вызов на
#     Helper.openUrl(...), который делает openVK_COMlink, а при false — openUrlInBrowser.
#
# Правки:
#   1) новый статический метод Api.normalizeAliasLinks(String)String;
#   2) вызов его над телом ответа перед return в sendRequestInternal;
#   3) NewsCursorAdapter$3.onClick: openVK_COMlink -> openUrl.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
changed = False

# --- (1)+(2) Api.sendRequestInternal: нормализация alias-разметки ---
A = "decode/smali/com/perm/kate/api/Api.smali"
s = open(A).read()
if "normalizeAliasLinks" in s:
    print("f12: Api уже пропатчен")
else:
    helper = r'''.method private static normalizeAliasLinks(Ljava/lang/String;)Ljava/lang/String;
    .locals 2

    if-eqz p0, :cond_0

    const-string v0, "\\[#alias\\|([^|]*)\\|([^\\]]*)\\]"

    invoke-static {v0}, Ljava/util/regex/Pattern;->compile(Ljava/lang/String;)Ljava/util/regex/Pattern;

    move-result-object v0

    invoke-virtual {v0, p0}, Ljava/util/regex/Pattern;->matcher(Ljava/lang/CharSequence;)Ljava/util/regex/Matcher;

    move-result-object v0

    const-string v1, "[$2|$1]"

    invoke-virtual {v0, v1}, Ljava/util/regex/Matcher;->replaceAll(Ljava/lang/String;)Ljava/lang/String;

    move-result-object p0

    :cond_0
    return-object p0
.end method

'''
    m_anchor = ".method public final sendRequestInternal(Ljava/lang/String;Ljava/lang/String;Z)Ljava/lang/String;\n"
    assert m_anchor in s, "f12: sendRequestInternal не найден"
    s = s.replace(m_anchor, helper + m_anchor, 1)

    anchor = ("    invoke-static {p3}, Lcom/perm/utils/Utils;->convertStreamToString(Ljava/io/InputStream;)Ljava/lang/String;\n"
              "\n"
              "    move-result-object p1\n"
              "    :try_end_0\n")
    add = ("    invoke-static {p3}, Lcom/perm/utils/Utils;->convertStreamToString(Ljava/io/InputStream;)Ljava/lang/String;\n"
           "\n"
           "    move-result-object p1\n"
           "\n"
           "    invoke-static {p1}, Lcom/perm/kate/api/Api;->normalizeAliasLinks(Ljava/lang/String;)Ljava/lang/String;\n"
           "\n"
           "    move-result-object p1\n"
           "    :try_end_0\n")
    assert anchor in s, "f12: якорь тела ответа (convertStreamToString) не найден"
    s = s.replace(anchor, add, 1)
    open(A, "w").write(s)
    changed = True
    print("f12: Api -> normalizeAliasLinks + вызов в sendRequestInternal")

# --- (3) NewsCursorAdapter$3.onClick: openVK_COMlink -> openUrl ---
N = "decode/smali/com/perm/kate/NewsCursorAdapter$3.smali"
s = open(N).read()
old = "    invoke-static {v0, p1}, Lcom/perm/kate/Helper;->openVK_COMlink(Ljava/lang/String;Landroid/content/Context;)Z\n"
new = "    invoke-static {v0, p1}, Lcom/perm/kate/Helper;->openUrl(Ljava/lang/String;Landroid/content/Context;)V\n"
if old not in s:
    assert new in s, "f12: якорь openVK_COMlink в NewsCursorAdapter$3 не найден"
    print("f12: NewsCursorAdapter$3 уже пропатчен")
else:
    s = s.replace(old, new, 1)
    open(N, "w").write(s)
    changed = True
    print("f12: NewsCursorAdapter$3 -> openUrl")

if not changed:
    print("f12: ничего менять не потребовалось")
PYEOF
