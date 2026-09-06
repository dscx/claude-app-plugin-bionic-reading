---
name: bionic-reading
description: Render text in bionic reading - a bold fixation prefix on each word - in an artifact, an HTML page, or a Markdown, text or Word document written to disk. Use whenever bionic reading is on and you are producing something other than a plain chat reply, or when asked to bionic, un-bionic, or adjust the fixation strength of a file.
---

# Bionic reading

Bionic reading bolds the first letters of each word. The eye fixes on the bold
part and the mind completes the rest, so the line is scanned rather than read
letter by letter.

**Bio**nic **rea**ding **ma**kes **wo**rds **eas**ier **t**o **sc**an.

The whole effect is one table. Letters bolded, by the number of letters in the
word:

| Letters in the word | Bolded |
| ------------------- | ------ |
| 1                   | none   |
| 2-3                 | 1      |
| 4-5                 | 2      |
| 6-7                 | 3      |
| 8-9                 | 4      |
| 10 or more          | 5      |

Each part of a hyphenated or slashed compound counts as its own word:
**twe**lve-**let**ter. A one-letter word is left plain - it needs no fixation
point, and bolding it whole would be indistinguishable from real emphasis.

## The rule that matters most

**Change nothing but the weight.** Same wording, same structure, same markup,
same styles. Bold is now a reading guide rather than emphasis, so do not add or
remove any, and leave text that was already bold or italic alone.

Never bionic, and never alter:

- fenced code blocks, indented code, and inline code
- file paths, URLs, commands, flags, identifiers, environment variables
- numbers, versions, and acronyms in capitals
- Markdown or HTML syntax itself, front matter, and table delimiter rows

Headings, list items, table cells, blockquotes, alt text and the visible text of
a link are prose. Bionic those.

## Do not do this by hand

Two tools ship with this plugin. Both are exact, and both are far more reliable
than bolding word by word. Reach for them whenever the output is a file or an
artifact rather than a chat reply.

### Artifacts and HTML pages

Inline the renderer at the end of the page, inside a `<script>` tag:

```
${CLAUDE_PLUGIN_ROOT}/assets/bionic.js
```

Read that file and paste its contents in. Artifacts cannot load scripts from
arbitrary hosts, so it has to be inlined - it is dependency-free and about 170
lines. It walks the document's text nodes, wraps each fixation prefix in
`<b class="bionic">`, and leaves the DOM, the text content and every style
exactly as they were. It skips `code`, `pre`, `kbd`, `samp`, `script`, `style`,
`textarea`, `svg`, `math` and anything already bold, keeps watching for content
added later, and is safe to run twice.

Put `data-no-bionic` on any element whose subtree should stay plain.

Build the page as you normally would - the design decisions are unchanged - and
add the script last.

### Markdown, text and other files on disk

Run the converter over the finished file:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/bionicize.py" -i notes.md
```

Useful flags:

- `--strip` removes the bionic bold again, restoring the file byte for byte
- `--plain` treats the input as plain text rather than Markdown
- `-o PATH` writes elsewhere instead of rewriting in place
- no file argument reads stdin and writes stdout

Write the document first, in whatever form it should take, then convert it as
the last step. Do not compose in bionic - the converter is exact and you are
not.

### Word, PowerPoint and PDF

No converter ships for these. Apply the table above when you build the runs:
split each word into a bold run and a regular run, and leave code, monospaced
text and figures alone. If the document is long, generate the Markdown, convert
it with `bionicize.py`, and let the usual document skill turn `**...**` into
bold runs.

## Turning it off

`/bionic off` stops it. The state lives in `~/.claude/bionic-reading/state`. If
someone asks for a file to be readable again, `--strip` is the answer rather
than regenerating it.
