#!/bin/sh
# claude-bionic-reading - checks. No dependencies beyond sh, python3 and, if
# it happens to be installed, node.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP="$ROOT/tests/.tmp"
rm -rf "$TMP"; mkdir -p "$TMP"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi; }

echo "manifests"
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
	if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$ROOT/$f" 2>/dev/null; then
		ok "$f is valid JSON"
	else
		bad "$f is valid JSON"
	fi
done
# The CLI auto-loads hooks/hooks.json; naming it again in the manifest makes the
# plugin fail to load.
if python3 -c "
import json,sys
m=json.load(open(sys.argv[1]))
h=m.get('hooks')
sys.exit(1 if h and 'hooks/hooks.json' in json.dumps(h) else 0)" "$ROOT/.claude-plugin/plugin.json"; then
	ok "manifest does not re-declare hooks/hooks.json"
else
	bad "manifest does not re-declare hooks/hooks.json"
fi

echo "hook"
OUT=$(echo '{"session_id":"t","prompt":"hello"}' | CLAUDE_BIONIC_STATE="$TMP/none" sh "$ROOT/hooks/user-prompt-submit.sh")
if printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d['hookSpecificOutput']['hookEventName']=='UserPromptSubmit'
assert len(d['hookSpecificOutput']['additionalContext'])>200
" 2>/dev/null; then
	ok "emits valid additionalContext when no state file exists"
else
	bad "emits valid additionalContext when no state file exists"
fi
printf 'off\n' > "$TMP/state"
OUT=$(echo '{}' | CLAUDE_BIONIC_STATE="$TMP/state" sh "$ROOT/hooks/user-prompt-submit.sh")
check "silent when off" "$OUT" ""
printf 'on\n' > "$TMP/state"
OUT=$(echo '{}' | CLAUDE_BIONIC_STATE="$TMP/state" sh "$ROOT/hooks/user-prompt-submit.sh" | wc -c | tr -d ' ')
if [ "$OUT" -gt 200 ]; then ok "speaks when on"; else bad "speaks when on" "$OUT bytes"; fi
echo '{}' | CLAUDE_BIONIC_STATE="$TMP/state" sh "$ROOT/hooks/user-prompt-submit.sh" >/dev/null 2>&1
check "exits 0" "$?" "0"

echo "converter"
# A function, not a string: "$B" would quote two words into one command name.
# printf | rather than a herestring, so this stays POSIX sh.
b()  { python3 "$ROOT/scripts/bionicize.py" "$@"; }
conv()  { printf '%s\n' "$1" | python3 "$ROOT/scripts/bionicize.py"; }
convp() { printf '%s\n' "$1" | python3 "$ROOT/scripts/bionicize.py" --plain; }

check "prefix table" "$(convp 'a to the words reading elephants extraordinary')" \
	'a **t**o **t**he **wo**rds **rea**ding **elep**hants **extra**ordinary'
check "hyphen splits" "$(convp 'twelve-letter')" '**twe**lve-**let**ter'
check "contraction" "$(convp "don't")" "**do**n't"
check "acronym left whole" "$(convp 'HTTP and API')" 'HTTP **a**nd API'
check "path left whole" "$(convp './src/app.js and ~/Dev')" './src/app.js **a**nd ~/Dev'
check "filename left whole" "$(convp 'open config.json now')" '**op**en config.json **n**ow'
check "inline code left whole" "$(conv 'run `npm install` now')" '**r**un `npm install` **n**ow'
check "url left whole" "$(conv 'see https://a.example/b now')" '**s**ee https://a.example/b **n**ow'
check "link text only" "$(conv '[the docs](https://a.example)')" '[**t**he **do**cs](https://a.example)'
check "existing bold untouched" "$(conv 'a **bold run** and *italics*')" 'a **bold run** **a**nd *italics*'
check "table delimiter" "$(conv '| --- | --- |')" '| --- | --- |'
check "numbers" "$(convp 'version 1.2.3 and 42')" '**ver**sion 1.2.3 **a**nd 42'
check "one-letter word stays plain" "$(convp 'a I am')" 'a I **a**m'

b "$ROOT/tests/fixture.md" > "$TMP/out.md"
b --strip "$TMP/out.md" > "$TMP/back.md"
if diff -q "$ROOT/tests/fixture.md" "$TMP/back.md" >/dev/null; then
	ok "--strip restores the original byte for byte"
else
	bad "--strip restores the original byte for byte"
fi
if grep -q 'const word = "reading";' "$TMP/out.md" && ! grep -q '[*][*]co[*][*]nst' "$TMP/out.md"; then
	ok "fenced code survives untouched"
else
	bad "fenced code survives untouched"
fi
if grep -q '^title: Front matter stays put$' "$TMP/out.md"; then
	ok "front matter survives untouched"
else
	bad "front matter survives untouched"
fi
b --plain "$ROOT/tests/fixture.md" | b --strip > "$TMP/plain.md"
if diff -q "$ROOT/tests/fixture.md" "$TMP/plain.md" >/dev/null; then
	ok "plain mode round trips too"
else
	bad "plain mode round trips too"
fi

echo "renderer"
if command -v node >/dev/null 2>&1; then
	if node -e "new Function(require('fs').readFileSync('$ROOT/assets/bionic.js','utf8'))" 2>/dev/null; then
		ok "assets/bionic.js parses"
	else
		bad "assets/bionic.js parses"
	fi
	if node -e "
const s=require('fs').readFileSync('$ROOT/assets/bionic.js','utf8');
const py=require('fs').readFileSync('$ROOT/scripts/bionicize.py','utf8');
const j=[...s.matchAll(/n <= (\d+)\) return (\d+)/g)].map(m=>m[1]+':'+m[2]).join(',');
const p=[...py.matchAll(/n <= (\d+):\n *return (\d+)/g)].map(m=>m[1]+':'+m[2]).join(',');
if(j!==p) throw new Error('js '+j+' vs py '+p);
" 2>/dev/null; then
		ok "js and python fixation tables agree"
	else
		bad "js and python fixation tables agree"
	fi
else
	printf '  skip  node not installed\n'
fi
python3 -m py_compile "$ROOT/scripts/bionicize.py" && ok "bionicize.py compiles" || bad "bionicize.py compiles"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
rm -rf "$TMP" "$ROOT/scripts/__pycache__"
[ "$FAIL" -eq 0 ]
