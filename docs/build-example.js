/*
 * Regenerate docs/example.html - the strength comparison used in the README.
 *
 *     node docs/build-example.js
 *
 * The rows are rendered here rather than in the browser, so the committed page
 * is plain static HTML: no script, no timing, and it looks the same wherever
 * it is opened. It renders through assets/bionic.js itself, so the picture in
 * the README cannot drift away from what the plugin actually does.
 */
const fs = require('fs');
const path = require('path');
const bionic = require(path.join(__dirname, '..', 'assets', 'bionic.js'));

const SENTENCE =
  'Bionic reading bolds the first letters of each word, so the eye lands on ' +
  'a fixation point and comprehension follows extraordinarily quickly.';

const ROWS = [
  ['default', 'tuned'],
  ['25', 'light'],
  ['40', 'medium'],
  ['75', 'heavy'],
];

const NOT_PROSE = /[_\\/@]|:{2}|\(\)|https?:|www\.|\d/;

function esc(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function render(text, strength) {
  bionic.setStrength(strength);
  return text.split(/(\s+)/).map(chunk => {
    if (/^\s+$/.test(chunk) || bionic.shouldSkipChunk(chunk)) return esc(chunk);
    // Keep any leading/trailing punctuation outside the word.
    const m = chunk.match(/^([^\p{L}]*)(.*?)([^\p{L}]*)$/u);
    const [, lead, word, tail] = m;
    if (!word) return esc(chunk);
    const [head, rest] = bionic.split(word);
    if (!head) return esc(chunk);
    return esc(lead) + '<b>' + esc(head) + '</b>' + esc(rest) + esc(tail);
  }).join('');
}

const rows = ROWS.map(([s, label]) => `
<div class="row"><span class="tag"><b>${s}</b>${label}</span>
<p>${render(SENTENCE, s)}</p></div>`).join('');

fs.writeFileSync(path.join(__dirname, 'example.html'), `<!doctype html>
<meta charset="utf-8"><title>bionic reading strengths</title>
<style>
 :root{--fg:#18181b;--mut:#71717a;--line:#e4e4e7;--bg:#fff;--chip:#f4f4f5}
 *{box-sizing:border-box}
 body{margin:0;padding:34px 38px;background:var(--bg);color:var(--fg);width:780px;
      font:17px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif}
 h1{font-size:13px;letter-spacing:.1em;text-transform:uppercase;color:var(--mut);
    margin:0 0 20px;font-weight:600}
 .row{display:grid;grid-template-columns:92px 1fr;gap:22px;align-items:baseline;
      padding:14px 0;border-top:1px solid var(--line)}
 .row:last-of-type{border-bottom:1px solid var(--line)}
 .tag{font:600 12px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace;color:var(--mut);
      background:var(--chip);border-radius:5px;padding:4px 8px;text-align:center}
 .tag b{display:block;font-weight:600;color:var(--fg);font-size:13px}
 p{margin:0}
 b{font-weight:bolder}
 code{font:14px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;
      background:var(--chip);border-radius:4px;padding:.12em .35em;font-weight:400}
 .note{margin:20px 0 0;color:var(--mut);font-size:14px}
</style>
<h1>How much of each word is bolded</h1>
${rows}
<p class="note">The default is roughly 40% with a five-letter ceiling, so the two
part company only on a long word: <b>extra</b>ordinarily against
<b>extrao</b>rdinarily. Code is never touched at any strength &mdash;
<code>const word = "reading";</code> &mdash; nor paths, URLs, flags, versions or
capitalised acronyms.</p>
`);
console.log('docs/example.html rebuilt');
