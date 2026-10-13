#!/bin/sh
# патч f10: автоматическая догрузка всего списка диалогов.
# i)   page count 30 -> 200 (VK max для getConversations) в refresh() и loadMore() ($15)
# ii)  loadMore() делаем public (чтобы inner-классы могли звать)
# iii) после каждой страницы callback-и ($6$1/$16$1) ставят state=1 и запускают loadMore(),
#      пока страница полная (>15). Так весь список грузится сразу, без прокрутки.
K="$(dirname "$0")/../"
cd "$K" || exit 1

python3 - <<'EOF'
mf = "decode/smali/com/perm/kate/MessagesFragment.smali"
s = open(mf).read()

if ".method public loadMore()V" in s:
    print("f10: уже пропатчен")
    raise SystemExit(0)

# i) restore count=200 in refresh()
old = """    const-wide/16 v3, 0x0

    const/16 v5, 0x1e

    invoke-virtual/range {v2 .. v8}, Lcom/perm/kate/session/Session;->getMessagesDialogs(JIZLcom/perm/kate/session/Callback;Landroid/app/Activity;)V"""
assert old in s, "f10: anchor refresh() не найден"
s = s.replace(old, old.replace("0x1e", "0xc8"), 1)

# ii) loadMore public + call-site invoke-virtual
assert ".method private loadMore()V" in s, "f10: loadMore не найден"
s = s.replace(".method private loadMore()V", ".method public loadMore()V", 1)
assert "invoke-direct {p0}, Lcom/perm/kate/MessagesFragment;->loadMore()V" in s, "f10: call-site loadMore не найден"
s = s.replace("invoke-direct {p0}, Lcom/perm/kate/MessagesFragment;->loadMore()V",
              "invoke-virtual {p0}, Lcom/perm/kate/MessagesFragment;->loadMore()V", 1)
open(mf, "w").write(s)

# i) count=200 в loadMore() ($15)
f15 = "decode/smali/com/perm/kate/MessagesFragment$15.smali"
s = open(f15).read()
assert "    const/16 v5, 0x1e" in s, "f10: $15 count не найден"
open(f15, "w").write(s.replace("    const/16 v5, 0x1e", "    const/16 v5, 0xc8", 1))

# iii) авто-цепочка в $6$1 и $16$1
for fn, cl in [("decode/smali/com/perm/kate/MessagesFragment$6$1.smali", "MessagesFragment$6"),
               ("decode/smali/com/perm/kate/MessagesFragment$16$1.smali", "MessagesFragment$16")]:
    s = open(fn).read()
    old = """    iget-object v0, v1, Lcom/perm/kate/%s;->this$0:Lcom/perm/kate/MessagesFragment;

    const/4 v1, 0x0

    invoke-static {v0, v1}, Lcom/perm/kate/MessagesFragment;->-$$Nest$fputstate(Lcom/perm/kate/MessagesFragment;I)V

    return-void""" % cl
    new = """    iget-object v0, v1, Lcom/perm/kate/%s;->this$0:Lcom/perm/kate/MessagesFragment;

    const/4 v1, 0x1

    invoke-static {v0, v1}, Lcom/perm/kate/MessagesFragment;->-$$Nest$fputstate(Lcom/perm/kate/MessagesFragment;I)V

    invoke-virtual {v0}, Lcom/perm/kate/MessagesFragment;->loadMore()V

    return-void""" % cl
    assert old in s, "f10: anchor не найден в " + fn
    open(fn, "w").write(s.replace(old, new, 1))

print("f10: авто-догрузка включена (count=200 + chain loadMore)")
EOF
