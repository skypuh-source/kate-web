#!/bin/sh
set -eu

cd "$(git rev-parse --show-toplevel)"

name1='[Мм]урда'
name2='сов'
name3='[Ии]го'
name4='рь'
user1='igormur'
user2='dasov'
uid1='165654'
uid2='293'
mail1='skypuh@gmail'
mail2='.com'
local1='dev'
local2='@local'
patterns="${name1}${name2}|${name3}${name4}|[Ii]${user1}${user2}|[Mm]ur${user2}|${uid1}${uid2}|${mail1}${mail2}|${local1}${local2}|/Users/[A-Za-z0-9._-]+"

identity="${PRIVACY_IDENTITY:-$(git log -1 --format='%an <%ae> %cn <%ce>' 2>/dev/null || true)}"
if [ -n "$identity" ] && printf '%s' "$identity" | grep -Eq "$patterns"; then
  printf '%s\n' 'Privacy check failed: personal data in commit identity.' >&2
  exit 1
fi

hits=$(git grep -l -a -E "$patterns" -- . \
  ':(exclude)scripts/check_privacy.sh' \
  ':(exclude).github/workflows/privacy.yml' \
  ':(exclude)*.apk' \
  ':(exclude)*.dex' \
  ':(exclude)*.arsc' \
  ':(exclude)*.jar' \
  ':(exclude)*.so' \
  ':(exclude)*.zip' \
  ':(exclude)*.png' \
  ':(exclude)*.jpg' \
  ':(exclude)*.jpeg' \
  ':(exclude)*.webp' \
  ':(exclude)*.gif' \
  ':(exclude)*.ttf' \
  ':(exclude)*.otf' \
  2>/dev/null || true)

if [ -n "$hits" ]; then
  printf '%s\n' 'Privacy check failed: personal data found in:' >&2
  printf '%s\n' "$hits" | sed 's/^/  /' >&2
  exit 1
fi

printf '%s\n' 'Privacy check passed.'
