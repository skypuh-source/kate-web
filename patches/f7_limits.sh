#!/bin/sh
# патч f7: убрать искусственный дневной лимит API этого APK
# 1) Api.sendRequest — обойти проверку api_count >= API_DAY_LIMIT
# 2) ApiCounter.init — не читать лимит из prefs, форсить огромный; счётчик = 0
# 3) UpdateChecker — не давать серверу автора перезаписывать API_DAY_LIMIT
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'EOF'
# 1) Api.smali: снять проверку лимита
f = "decode/smali/com/perm/kate/api/Api.smali"
s = open(f).read()
if ":cond_limit_off" in s:
    print("f7: Api уже пропатчен")
else:
    old = """    if-ge v0, v1, :cond_7

    .line 136
    invoke-virtual {p0, p1, p2}, Lcom/perm/kate/api/Api;->getSignedUrl(Lcom/perm/kate/api/Params;Z)Ljava/lang/String;"""
    new = """    if-ge v0, v1, :cond_limit_off

    :cond_limit_off
    .line 136
    invoke-virtual {p0, p1, p2}, Lcom/perm/kate/api/Api;->getSignedUrl(Lcom/perm/kate/api/Params;Z)Ljava/lang/String;"""
    assert old in s, "f7: якорь проверки лимита не найден"
    s = s.replace(old, new, 1)
    open(f, "w").write(s)
    print("f7: Api.sendRequest лимит обойдён")

# 2) ApiCounter.smali: форсить значения
f = "decode/smali/com/perm/utils/ApiCounter.smali"
s = open(f).read()
if "0x7fffffff" in s:
    print("f7: ApiCounter уже пропатчен")
else:
    old_lim = """    const-string v1, "adl"

    const/16 v2, 0xa

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getInt(Ljava/lang/String;I)I

    move-result v0

    sput v0, Lcom/perm/kate/api/Api;->API_DAY_LIMIT:I"""
    new_lim = """    const v0, 0x7fffffff

    sput v0, Lcom/perm/kate/api/Api;->API_DAY_LIMIT:I"""
    assert old_lim in s, "f7: якорь adl не найден"
    s = s.replace(old_lim, new_lim, 1)

    old_cnt = """    const-string v1, "adlc"

    const/4 v2, 0x0

    invoke-interface {v0, v1, v2}, Landroid/content/SharedPreferences;->getInt(Ljava/lang/String;I)I

    move-result v0

    invoke-static {v0}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v0

    sput-object v0, Lcom/perm/kate/api/Api;->api_count:Ljava/lang/Integer;"""
    new_cnt = """    const/4 v0, 0x0

    const/4 v2, 0x0

    invoke-static {v0}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    move-result-object v0

    sput-object v0, Lcom/perm/kate/api/Api;->api_count:Ljava/lang/Integer;"""
    assert old_cnt in s, "f7: якорь adlc не найден"
    s = s.replace(old_cnt, new_cnt, 1)
    open(f, "w").write(s)
    print("f7: ApiCounter.init нейтрализован")

# 3) UpdateChecker.smali: убрать sput лимита
f = "decode/smali/com/perm/utils/UpdateChecker.smali"
s = open(f).read()
old = "    sput p0, Lcom/perm/kate/api/Api;->API_DAY_LIMIT:I"
if old not in s:
    print("f7: UpdateChecker уже пропатчен")
else:
    s = s.replace(old, "    nop", 1)
    open(f, "w").write(s)
    print("f7: UpdateChecker sput лимита удалён")
EOF
