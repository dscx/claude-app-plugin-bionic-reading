# claude-bionic-reading

Bionic reading bolds the first letters of each word. The eye lands on the bold
part, the mind fills in the rest, and a line gets scanned instead of read letter
by letter. This plugin puts that in front of everything Claude Code writes.

**Bio**nic **rea**ding **ma**kes **wo**rds **eas**ier **t**o **sc**an.

It covers three places, in the way that suits each:

| Where | How | Exact? |
| ----- | --- | ------ |
| Replies in the chat | a `UserPromptSubmit` hook restates the fixation rules each turn | model-applied |
| Artifacts and HTML pages | a dependency-free script inlined into the page | yes |
| Markdown, text and other files on disk | a converter run over the finished file | yes |

Nothing else changes. Same wording, same structure, same Markdown, same styles.
Bold stops meaning emphasis and starts meaning *look here*, so no emphasis is
added or removed anywhere.

**Code is never touched.** Not fenced blocks, not indented blocks, not inline
spans, and not the things that read like code in the middle of a sentence —
paths, URLs, flags, identifiers, environment variables, versions, numbers and
capitalised acronyms all keep their shape.

## Install

Three routes to the same result.

### In the Claude Code app

**Settings → Extensions → Browse Extensions → Plugins → Add → Add Marketplace**,
then paste the repository:

```
dscx/claude-app-plugin-bionic-reading
```

Install **Bionic Reading** from the marketplace that appears.

### From the CLI

```bash
claude plugin marketplace add dscx/claude-app-plugin-bionic-reading
```

```bash
claude plugin install claude-bionic-reading@claude-bionic-reading
```

### From a clone

```bash
git clone https://github.com/dscx/claude-app-plugin-bionic-reading.git
```

```bash
claude plugin marketplace add ./claude-app-plugin-bionic-reading
```

It is on the moment it is enabled. Start a new session, or send one more
message in the current one, and the replies arrive bionic.

## Use

```
/bionic          toggle
/bionic on
/bionic off
/bionic status
```

The state is a single word in `~/.claude/bionic-reading/state`. A missing file
means on. Point `CLAUDE_BIONIC_STATE` elsewhere to move it.

Turning it off silences the hook from the next turn onward. It does not rewrite
anything already produced — for that, see `--strip` below.

## The table

The entire look of bionic reading is one table. Letters bolded, by the number of
letters in the word:

| Letters in the word | Bolded |
| ------------------- | ------ |
| 1                   | none   |
| 2–3                 | 1      |
| 4–5                 | 2      |
| 6–7                 | 3      |
| 8–9                 | 4      |
| 10 or more          | 5      |

Each part of a hyphenated or slashed compound counts as its own word:
**twe**lve-**let**ter. A one-letter word is left plain — it needs no fixation
point, and bolding it whole would be indistinguishable from real emphasis,
which would make the transform irreversible.

To read heavier or lighter, edit `prefixLetters` in
[`assets/bionic.js`](assets/bionic.js) and `prefix_letters` in
[`scripts/bionicize.py`](scripts/bionicize.py). They are the same table twice;
keep them in step.

## Converting files yourself

```bash
python3 scripts/bionicize.py notes.md > notes.bionic.md
```

```bash
python3 scripts/bionicize.py -i notes.md
```

```bash
python3 scripts/bionicize.py --strip -i notes.md
```

`--strip` is exact: it removes a `**…**` run that ends in the middle of a word,
which is the one thing this converter produces and normal writing never does.
Real emphasis survives untouched, so the round trip is byte for byte.

Other flags: `--plain` treats input as plain text rather than Markdown, `-o`
writes elsewhere, and with no file argument it reads stdin. Standard library
only, no dependencies.

## Converting a page yourself

Paste [`assets/bionic.js`](assets/bionic.js) into a `<script>` tag at the end of
the page. It walks the text nodes, wraps each fixation prefix in
`<b class="bionic">`, and leaves the DOM, the text and every style as they were.
It skips `code`, `pre`, `kbd`, `samp`, `script`, `style`, `textarea`, `svg`,
`math` and anything already bold, keeps watching for content added later, and is
safe to run more than once.

Opt a subtree out with `data-no-bionic`:

```html
<blockquote data-no-bionic>Quoted verbatim, so left alone.</blockquote>
```

Fixations are `font-weight: bolder`, which is relative — a prefix stays heavier
than whatever weight it sits in, and inherits everything else.

Open [`tests/demo.html`](tests/demo.html) in a browser to see it working.

## What to expect

The two converters are deterministic and exact. **The chat replies are not.**
There is no rendering layer to hook into, so the hook asks the model to write
its prose that way, and a model applying a rule thousands of times per
conversation will not be perfect. Expect the occasional missed word, and expect
it to lapse for a moment after a long tool result. Replies also grow by roughly
four characters per word, which costs output tokens.

Both are the price of doing this without a client that supports it natively. If
what you want is exactness, ask for a document or an artifact — those go through
the converters.

Bolding inside a word relies on CommonMark's intra-word strong emphasis
(`**Bio**nic`). Every renderer in Claude Code handles it. Some other Markdown
tools do not.

## What is in here

```
.claude-plugin/plugin.json    manifest
hooks/hooks.json              one UserPromptSubmit hook
hooks/user-prompt-submit.sh   restates the rules each turn, honours the toggle
commands/bionic.md            /bionic
skills/bionic-reading/        how to bionic an artifact or a document
assets/bionic.js              the renderer for HTML
scripts/bionicize.py          the converter for Markdown and text
tests/run-tests.sh            the checks
```

The hook never reads the submitted prompt. It drains stdin, drops it, and writes
a fixed block of text. Nothing is logged and nothing leaves the machine.

## Tests

```bash
tests/run-tests.sh
```

## Licence

MIT. See [LICENSE](LICENSE).
