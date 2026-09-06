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

printf 'on\n' > "$TMP/state"
for S in default 25 40 75; do
	printf '%s\n' "$S" > "$TMP/strength"
	N=$(echo '{}' | CLAUDE_BIONIC_STATE="$TMP/state" \
		CLAUDE_BIONIC_STRENGTH_FILE="$TMP/strength" \
		sh "$ROOT/hooks/user-prompt-submit.sh" | grep -c "Prefix length")
	check "hook states a table at strength $S" "$N" "1"
done
DEF=$(printf 'default\n' > "$TMP/strength"; echo '{}' | CLAUDE_BIONIC_STRENGTH_FILE="$TMP/strength" sh "$ROOT/hooks/user-prompt-submit.sh")
HVY=$(printf '75\n' > "$TMP/strength"; echo '{}' | CLAUDE_BIONIC_STRENGTH_FILE="$TMP/strength" sh "$ROOT/hooks/user-prompt-submit.sh")
if [ "$DEF" != "$HVY" ]; then ok "the table differs by strength"; else bad "the table differs by strength"; fi

echo "converter"
# A function, not a string: "$B" would quote two words into one command name.
# printf | rather than a herestring, so this stays POSIX sh.
b()  { python3 "$ROOT/scripts/bionicize.py" "$@"; }
conv()  { printf '%s\n' "$1" | python3 "$ROOT/scripts/bionicize.py"; }
convp() { printf '%s\n' "$1" | python3 "$ROOT/scripts/bionicize.py" --plain; }
convs() { printf '%s\n' "$2" | python3 "$ROOT/scripts/bionicize.py" --plain --strength "$1"; }

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

check "strength 25" "$(convs 25 'reading extraordinarily')" '**re**ading **extr**aordinarily'
check "strength 40" "$(convs 40 'reading extraordinarily')" '**rea**ding **extrao**rdinarily'
check "strength 75" "$(convs 75 'reading extraordinarily')" '**readi**ng **extraordina**rily'
# A bionic run must always be followed by a letter, or --strip cannot tell it
# from real emphasis. At 75 the naive cut lands on the apostrophe.
check "75 never cuts on an apostrophe" "$(convs 75 "don't")" "**do**n't"
for S in default 25 40 75; do
	if b --strength "$S" "$ROOT/tests/fixture.md" | b --strip \
		| cmp -s - "$ROOT/tests/fixture.md"; then
		ok "--strip is exact at strength $S"
	else
		bad "--strip is exact at strength $S"
	fi
done
if b --strength 99 "$ROOT/tests/fixture.md" >/dev/null 2>&1; then
	bad "an unknown strength is rejected"
else
	ok "an unknown strength is rejected"
fi

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
	node -e "
const js=require('$ROOT/assets/bionic.js');
const out=[];
for (const s of ['default','25','40','75']) { js.setStrength(s);
  out.push(s+':'+Array.from({length:24},(_,i)=>js.prefixLetters(i+1)).join(',')); }
require('fs').writeFileSync('$TMP/js.txt', out.join('\\n')+'\\n');
" 2>/dev/null
	python3 -c "
import sys; sys.path.insert(0,'$ROOT/scripts')
import bionicize as b
open('$TMP/py.txt','w').write(''.join(
    s+':'+','.join(str(b.prefix_letters(n,s)) for n in range(1,25))+'\\n'
    for s in ('default','25','40','75')))
" 2>/dev/null
	if diff -q "$TMP/js.txt" "$TMP/py.txt" >/dev/null 2>&1; then
		ok "js and python agree at every strength, lengths 1-24"
	else
		bad "js and python agree at every strength, lengths 1-24"
	fi
	node -e "
const js=require('$ROOT/assets/bionic.js');
const w=['a','to','the',\"don't\",\"o'clock\",'reading','extraordinarily'];
const out=[];
for (const s of ['default','25','40','75']) { js.setStrength(s);
  out.push(s+' '+w.map(x=>{const p=js.split(x);return p[0]?'**'+p[0]+'**'+p[1]:x;}).join(' ')); }
require('fs').writeFileSync('$TMP/jt.txt', out.join('\\n')+'\\n');
" 2>/dev/null
	python3 -c "
import sys; sys.path.insert(0,'$ROOT/scripts')
import bionicize as b
w=['a','to','the',\"don't\",\"o'clock\",'reading','extraordinarily']
lines=[]
for s in ('default','25','40','75'):
    b._strength=s
    lines.append(s+' '+' '.join((lambda h,t: '**'+h+'**'+t if h else x)(*b.bionic_token(x)) for x in w))
open('$TMP/pt.txt','w').write('\\n'.join(lines)+'\\n')
" 2>/dev/null
	if diff -q "$TMP/jt.txt" "$TMP/pt.txt" >/dev/null 2>&1; then
		ok "js and python split identically, contractions included"
	else
		bad "js and python split identically, contractions included"
	fi
else
	printf '  skip  node not installed\n'
fi
python3 -m py_compile "$ROOT/scripts/bionicize.py" && ok "bionicize.py compiles" || bad "bionicize.py compiles"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
rm -rf "$TMP" "$ROOT/scripts/__pycache__"
[ "$FAIL" -eq 0 ]
