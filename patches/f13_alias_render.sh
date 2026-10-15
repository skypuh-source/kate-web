#!/bin/sh
# патч f13: разметка alias нового формата не рендерится (мусор "DISPLAY|URL", все ссылки
# выглядят слитыми, клик ведёт в несуществующий https://vk.com/#alias).
#
# Причина: web.api.vk.ru (v=5.289) отдаёт ссылки в постах/комментариях как
#     [#alias|DISPLAY|URL]        (адрес В КОНЦЕ)
# а ЕДИНЫЙ парсер Kate NewsCursorAdapter.spannableLink (используется лентой, стеной,
# WallMessageActivity, комментариями, диалогами, сообщениями, поиском, группами —
# через 3-арг overload) ожидает СТАРЫЙ формат
#     [URL|DISPLAY]               (адрес В НАЧАЛЕ)
# на pattern \[([^\]\[]*?)(:bp-\d*_\d*)?\|(.*?)\] .
# На новом формате group(1)="#alias", group(3)="DISPLAY|URL": в текст подставляется
# "DISPLAY|URL" (мусор), а ссылка = "https://vk.com/#alias".
#
# f12 нормализует тело ответа API, но это НЕ помогает уже закэшированным постам
# (в БД хранится сырой [#alias|...]). f13 чинит РЕНДЕР: перед разбором строки
# переписываем [#alias|DISPLAY|URL] -> [URL|DISPLAY] прямо в SpannableStringBuilder,
# так что работают и старые (кэш), и новые данные, во всех экранах.
#
# Правки в decode/smali/com/perm/kate/NewsCursorAdapter.smali:
#   1) новое статическое поле aliasPattern;
#   2) компиляция aliasPattern в <clinit>;
#   3) проход нормализации в начале spannableLink(7-арг) перед legacy-парсером.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'PYEOF'
changed = False
N = "decode/smali/com/perm/kate/NewsCursorAdapter.smali"
s = open(N).read()

if "aliasPattern" in s:
    print("f13: NewsCursorAdapter уже пропатчен")
else:
    # --- 1) статическое поле ---
    f_anchor = ".field public static final pattern:Ljava/util/regex/Pattern;\n"
    assert f_anchor in s, "f13: поле pattern не найдено"
    s = s.replace(
        f_anchor,
        f_anchor + "\n.field public static final aliasPattern:Ljava/util/regex/Pattern;\n",
        1,
    )

    # --- 2) инициализация в <clinit> ---
    c_anchor = ("    sput-object v0, Lcom/perm/kate/NewsCursorAdapter;->pattern:Ljava/util/regex/Pattern;\n"
                "\n"
                "    return-void\n")
    assert c_anchor in s, "f13: <clinit> pattern sput не найден"
    c_add = ("    sput-object v0, Lcom/perm/kate/NewsCursorAdapter;->pattern:Ljava/util/regex/Pattern;\n"
             "\n"
             "    .line 847\n"
             "    const-string v0, \"\\\\[#alias\\\\|([^|]*)\\\\|([^\\\\]]*)\\\\]\"\n"
             "\n"
             "    invoke-static {v0}, Ljava/util/regex/Pattern;->compile(Ljava/lang/String;)Ljava/util/regex/Pattern;\n"
             "\n"
             "    move-result-object v0\n"
             "\n"
             "    sput-object v0, Lcom/perm/kate/NewsCursorAdapter;->aliasPattern:Ljava/util/regex/Pattern;\n"
             "\n"
             "    return-void\n")
    s = s.replace(c_anchor, c_add, 1)

    # --- 3) проход нормализации в spannableLink(7-арг) ---
    m_anchor = ("    invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\n"
                "\n"
                "    .line 855\n"
                "    sget-object v1, Lcom/perm/kate/NewsCursorAdapter;->pattern:Ljava/util/regex/Pattern;\n")
    assert m_anchor in s, "f13: начало spannableLink(7-арг) не найдено"
    pre = (
        "    invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\n"
        "\n"
        "    sget-object v1, Lcom/perm/kate/NewsCursorAdapter;->aliasPattern:Ljava/util/regex/Pattern;\n"
        "\n"
        "    invoke-virtual {p0}, Landroid/text/SpannableStringBuilder;->toString()Ljava/lang/String;\n"
        "\n"
        "    move-result-object v2\n"
        "\n"
        "    invoke-virtual {v1, v2}, Ljava/util/regex/Pattern;->matcher(Ljava/lang/CharSequence;)Ljava/util/regex/Matcher;\n"
        "\n"
        "    move-result-object v1\n"
        "\n"
        "    :goto_alias\n"
        "    invoke-virtual {v1}, Ljava/util/regex/Matcher;->find()Z\n"
        "\n"
        "    move-result v2\n"
        "\n"
        "    if-eqz v2, :cond_alias\n"
        "\n"
        "    invoke-virtual {p0}, Landroid/text/SpannableStringBuilder;->toString()Ljava/lang/String;\n"
        "\n"
        "    move-result-object v2\n"
        "\n"
        "    invoke-virtual {v1}, Ljava/util/regex/Matcher;->group()Ljava/lang/String;\n"
        "\n"
        "    move-result-object v3\n"
        "\n"
        "    invoke-virtual {v2, v3}, Ljava/lang/String;->indexOf(Ljava/lang/String;)I\n"
        "\n"
        "    move-result v4\n"
        "\n"
        "    new-instance v5, Ljava/lang/StringBuilder;\n"
        "\n"
        "    invoke-direct {v5}, Ljava/lang/StringBuilder;-><init>()V\n"
        "\n"
        "    const-string v2, \"[\"\n"
        "\n"
        "    invoke-virtual {v5, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n"
        "\n"
        "    const/4 v2, 0x2\n"
        "\n"
        "    invoke-virtual {v1, v2}, Ljava/util/regex/Matcher;->group(I)Ljava/lang/String;\n"
        "\n"
        "    move-result-object v2\n"
        "\n"
        "    invoke-virtual {v5, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n"
        "\n"
        "    const-string v2, \"|\"\n"
        "\n"
        "    invoke-virtual {v5, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n"
        "\n"
        "    const/4 v2, 0x1\n"
        "\n"
        "    invoke-virtual {v1, v2}, Ljava/util/regex/Matcher;->group(I)Ljava/lang/String;\n"
        "\n"
        "    move-result-object v2\n"
        "\n"
        "    invoke-virtual {v5, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n"
        "\n"
        "    const-string v2, \"]\"\n"
        "\n"
        "    invoke-virtual {v5, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n"
        "\n"
        "    invoke-virtual {v5}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\n"
        "\n"
        "    move-result-object v5\n"
        "\n"
        "    invoke-virtual {v3}, Ljava/lang/String;->length()I\n"
        "\n"
        "    move-result v2\n"
        "\n"
        "    add-int/2addr v2, v4\n"
        "\n"
        "    invoke-virtual {p0, v4, v2, v5}, Landroid/text/SpannableStringBuilder;->replace(IILjava/lang/CharSequence;)Landroid/text/SpannableStringBuilder;\n"
        "\n"
        "    goto :goto_alias\n"
        "\n"
        "    :cond_alias\n"
        "\n"
        "    .line 855\n"
        "    sget-object v1, Lcom/perm/kate/NewsCursorAdapter;->pattern:Ljava/util/regex/Pattern;\n"
    )
    s = s.replace(m_anchor, pre, 1)

    open(N, "w").write(s)
    changed = True
    print("f13: NewsCursorAdapter -> aliasPattern + нормализация в spannableLink")

if not changed:
    print("f13: ничего менять не потребовалось")
PYEOF
