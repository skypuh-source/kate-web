#!/bin/sh
set -eu

cd "$(git rev-parse --show-toplevel)"

allowed='^(\.gitignore|README\.md|THIRD_PARTY_NOTICES\.md|assets/mascot/[^/]+|\.github/workflows/(privacy|release)\.yml|keys/debug\.keystore|orig/Kate_133_11\.apk|patches/f.+|scripts/(apply|build|check_privacy|check_scope|decode)\.sh|tools/apktool_2\.12\.1\.jar)$'

bad=$(git ls-files | grep -Ev "$allowed" || true)

if [ -n "$bad" ]; then
  printf '%s\n' 'Repository scope check failed: non-core files tracked:' >&2
  printf '%s\n' "$bad" | sed 's/^/  /' >&2
  printf '%s\n' 'Keep only build/release/security/README inputs, or update the allowlist explicitly.' >&2
  exit 1
fi

printf '%s\n' 'Repository scope check passed.'
