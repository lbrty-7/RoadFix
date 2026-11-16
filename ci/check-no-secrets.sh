#!/usr/bin/env bash
# Fails if a file that must stay private has been committed. The repo is
# public, so anything in git is visible to everyone, forever (even after a
# later commit removes it, it stays in the history).
set -euo pipefail

forbidden=(
  "RoadFix/GoogleService-Info.plist"   # Firebase config
  "RoadFix/Sentry-Info.plist"          # Sentry DSN
)

found=0
for path in "${forbidden[@]}"; do
  if git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
    echo "::error file=$path::$path must not be committed. Remove it with 'git rm --cached $path' (it is listed in .gitignore)."
    found=1
  fi
done

# Any .env file (except examples) is also private.
while IFS= read -r path; do
  case "$path" in
    *.example|*.sample) ;;
    *) echo "::error file=$path::Environment files must not be committed: $path"; found=1 ;;
  esac
done < <(git ls-files | grep -E '(^|/)\.env(\..*)?$' || true)

if [[ "$found" -ne 0 ]]; then
  exit 1
fi
echo "No private config or environment files are committed."
