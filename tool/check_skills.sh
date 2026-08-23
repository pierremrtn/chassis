#!/usr/bin/env bash
# Verification greps for chassis/skills, wired into CI (docs-check job).
#
# These are the checks documented under "Maintenance" in
# chassis/skills/README.md — run them locally before opening a PR:
#
#   bash tool/check_skills.sh
#
# Each grep must return ZERO hits; any hit is printed and fails the script.
set -u
cd "$(dirname "$0")/.."

fail=0

echo "== Voice check (no easy/magic/simply/just in SKILL.md) =="
# --include=SKILL.md keeps chassis/skills/README.md (which must name the
# banned words) out of the results.
if grep -rin 'easy\|magic\|simply\|just' --include=SKILL.md chassis/skills/; then
  echo "FAIL: banned voice words found (see doc_guidelines: no easy/magic/simply/just)"
  fail=1
else
  echo "OK"
fi

echo "== Removed-API check (symbols deleted in 1.0.0) =="
# The bracketed first letters keep this script from matching itself.
if grep -rn 'generate[Q]ueryHandler\|generate[C]ommandHandler\|[R]epositoryGenerator\|repository[_]builder\|mediator[_]name\|output[_]name\|app[_]mediator\.dart' chassis/skills/; then
  echo "FAIL: removed pre-1.0 API symbols found in chassis/skills/"
  fail=1
else
  echo "OK"
fi

echo "== English-only check =="
# --include keeps this script from matching its own character class.
if grep -rin '[éèêàç]' --include=SKILL.md chassis/skills/; then
  echo "FAIL: non-English characters found in SKILL.md files"
  fail=1
else
  echo "OK"
fi

exit "$fail"
