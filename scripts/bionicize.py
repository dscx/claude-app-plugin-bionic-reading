#!/usr/bin/env python3
"""claude-bionic-reading - convert Markdown or plain text to bionic reading.

Bolds the fixation prefix of each word of prose with ** markdown, and leaves
everything else byte-for-byte alone: fenced and indented code, inline code,
front matter, table delimiters, HTML tags, link targets, URLs, paths,
identifiers, numbers, entities, math, and text that was already bold.

    bionicize.py notes.md > notes.bionic.md
    bionicize.py -i notes.md              # rewrite in place
    bionicize.py --strength 75 notes.md   # bold three quarters of each word
    bionicize.py --strip -i notes.md      # undo it

The transform is reversible: --strip removes exactly the bold this script
adds (a ** run that ends mid-word) and leaves real emphasis untouched.

No dependencies beyond the standard library.
"""

import argparse
import re
import sys

# --------------------------------------------------------------------------
# How much of each word is bolded. "default" is a tuned table - roughly two
# fifths of the word with a five-letter ceiling, so a long word does not grow
# an absurd prefix. The numbered strengths are literal percentages.
#
# Two invariants hold at every strength, and both matter: a one-letter word is
# never bolded, and no word is ever bolded whole. A fully bolded word is
# indistinguishable from real emphasis, which is what would cost --strip its
# exactness. Keep assets/bionic.js in step.
# --------------------------------------------------------------------------
STRENGTHS = ("default", "25", "40", "75")
RATIOS = {"25": 0.25, "40": 0.40, "75": 0.75}

_strength = "default"


def prefix_letters(n, strength=None):
    if n <= 1:
        return 0
    ratio = RATIOS.get(strength or _strength)
    if ratio is None:
        if n <= 3:
            return 1
        if n <= 5:
            return 2
        if n <= 7:
            return 3
        if n <= 9:
            return 4
        return 5
    return min(n - 1, max(1, int(n * ratio + 0.5)))


WORD = re.compile(r"[^\W\d_]+(?:['’][^\W\d_]+)*")
LETTER = re.compile(r"[^\W\d_]")

# A whitespace-delimited chunk carrying any of these is a path, an identifier,
# a version, a URL or a number - not a word of prose.
NOT_PROSE = re.compile(r"[_\\/@]|::|\(\)|\d")

# config.json, app.tsx, Makefile.am ... bare filenames, no slash to give them
# away. Extension allowlist rather than a shape, so that "e.g." survives.
FILENAME = re.compile(
    r"^[\w.-]+\.(?:js|mjs|cjs|jsx|ts|tsx|py|rb|go|rs|java|kt|swift|c|h|cc|cpp|"
    r"cs|php|pl|sh|bash|zsh|fish|ps1|sql|md|mdx|rst|txt|json|jsonc|ya?ml|toml|"
    r"ini|cfg|conf|env|lock|html?|css|scss|sass|less|xml|svg|png|jpe?g|gif|"
    r"webp|pdf|csv|tsv|zip|tar|gz|log|plist|gradle|am|in)$",
    re.IGNORECASE,
)

FENCE = re.compile(r"^(?P<indent>[ \t]{0,3})(?P<f>`{3,}|~{3,})(?P<info>.*)$")
INDENT_CODE = re.compile(r"^(?: {4}|\t)\s*\S")
LIST_ITEM = re.compile(r"^[ \t]*(?:[-*+]|\d+[.)])\s")
TABLE_DELIM = re.compile(r"^\|?[\s:|-]*-[\s:|-]*\|?$")
FRONT_MATTER = re.compile(r"^(---|\+\+\+)\s*$")

# Spans copied through untouched. Order matters: earliest and longest wins.
PROTECTED = re.compile(
    r"""
      (?P<code>`+[^`]*`+)
    | (?P<comment><!--.*?-->)
    | (?P<tag><[^>\s][^>]*>)
    | (?P<refdef>^[ \t]*\[[^\]]+\]:[ \t]*\S+)
    | (?P<linkurl>\]\([^)]*\))
    | (?P<mathblock>\$\$[^$]*\$\$)
    | (?P<math>\$[^$\s][^$]*\$)
    | (?P<bold>\*\*\*[^*]+\*\*\*|\*\*[^*]+\*\*|__[^_]+__)
    | (?P<emph>\*[^*\s][^*]*\*|(?<![\w])_[^_\s][^_]*_(?![\w]))
    | (?P<entity>&(?:[A-Za-z][A-Za-z0-9]{1,10}|\#[0-9]{1,6}|\#x[0-9A-Fa-f]{1,6});)
    | (?P<url>(?:https?://|ftp://|mailto:|www\.)\S+)
    | (?P<footnote>\[\^[^\]]+\])
    """,
    re.VERBOSE,
)

# A ** run that stops in the middle of a word is one this script wrote.
UNBIONIC = re.compile(r"\*\*([^\s*]+)\*\*(?=[^\W\d_])")


def skip_chunk(chunk):
    """True when a whitespace-delimited chunk should be left alone."""
    if NOT_PROSE.search(chunk):
        return True
    core = chunk.strip(",;:!?()[]{}\"'‘’“”").rstrip(".")
    if core[:1] in (".", "~", "/") or FILENAME.match(core):
        return True
    # Acronyms: **AP**I reads worse than APl left whole.
    if len(core) >= 2 and core.isupper() and LETTER.search(core):
        return True
    return False


def bionic_token(token):
    """Split a word into (bold prefix, rest)."""
    letters = sum(1 for ch in token if LETTER.match(ch))
    want = prefix_letters(letters)
    if want <= 0:
        return "", token
    taken = 0
    cut = len(token)
    for i, ch in enumerate(token):
        if LETTER.match(ch):
            taken += 1
        if taken >= want:
            cut = i + 1
            break
    # A bionic run is always followed by a letter. That is the whole signature
    # --strip recognises, and without this a high strength cuts don't as
    # **don**'t, whose bold is followed by an apostrophe and so survives --strip
    # as if it were real emphasis.
    while cut > 0 and (cut >= len(token) or not LETTER.match(token[cut])):
        cut -= 1
    if cut <= 0:
        return "", token
    return token[:cut], token[cut:]


def bionic_text(text):
    """Bold every prose word in a run of already-unprotected text."""
    out = []
    pos = 0
    for m in WORD.finditer(text):
        start, end = m.span()
        # Widen to the whitespace-delimited chunk, so ./src/app.js and API_KEY
        # are judged whole rather than letter-run by letter-run.
        left = start
        while left > 0 and not text[left - 1].isspace():
            left -= 1
        right = end
        while right < len(text) and not text[right].isspace():
            right += 1
        if skip_chunk(text[left:right]):
            continue
        head, tail = bionic_token(m.group(0))
        if not head:
            continue
        out.append(text[pos:start])
        out.append("**" + head + "**" + tail)
        pos = end
    out.append(text[pos:])
    return "".join(out)


def bionic_line(line):
    out = []
    pos = 0
    for m in PROTECTED.finditer(line):
        out.append(bionic_text(line[pos : m.start()]))
        out.append(m.group(0))
        pos = m.end()
    out.append(bionic_text(line[pos:]))
    return "".join(out)


def convert(text, markdown=True):
    if not markdown:
        return "\n".join(bionic_line(ln) for ln in text.split("\n"))

    lines = text.split("\n")
    out = []
    fence = None
    in_front = False
    prev_blank = True

    for i, line in enumerate(lines):
        stripped = line.strip()
        keep = False

        if i == 0 and FRONT_MATTER.match(stripped):
            in_front, keep = True, True
        elif in_front:
            keep = True
            if FRONT_MATTER.match(stripped):
                in_front = False
        elif fence is not None:
            keep = True
            m = FENCE.match(line)
            if m and m.group("f")[0] == fence[0] and len(m.group("f")) >= len(fence) \
                    and not m.group("info").strip():
                fence = None
        else:
            m = FENCE.match(line)
            if m:
                fence, keep = m.group("f"), True
            elif prev_blank and INDENT_CODE.match(line) and not LIST_ITEM.match(line):
                keep = True
            elif TABLE_DELIM.match(stripped) and "-" in stripped:
                keep = True

        out.append(line if keep else bionic_line(line))
        prev_blank = stripped == ""

    return "\n".join(out)


def strip(text):
    return UNBIONIC.sub(r"\1", text)


def main(argv=None):
    p = argparse.ArgumentParser(
        prog="bionicize.py",
        description="Convert Markdown or plain text to bionic reading.",
    )
    p.add_argument("files", nargs="*", metavar="FILE",
                   help="input files; reads stdin when omitted")
    p.add_argument("-i", "--in-place", action="store_true",
                   help="rewrite each file instead of writing to stdout")
    p.add_argument("-o", "--output", metavar="PATH",
                   help="write to PATH instead of stdout (single input only)")
    p.add_argument("--strip", action="store_true",
                   help="remove bionic bold instead of adding it")
    p.add_argument("--plain", action="store_true",
                   help="treat input as plain text, not Markdown")
    p.add_argument("--strength", choices=STRENGTHS, default="default",
                   metavar="{default,25,40,75}",
                   help="percentage of each word to bold (default: default, "
                        "which is about 40%% with a five-letter ceiling)")
    args = p.parse_args(argv)

    if args.output and args.in_place:
        p.error("--output and --in-place are mutually exclusive")
    if args.output and len(args.files) > 1:
        p.error("--output takes a single input file")
    if args.in_place and not args.files:
        p.error("--in-place needs at least one file")

    global _strength
    _strength = args.strength

    run = strip if args.strip else (lambda t: convert(t, markdown=not args.plain))

    if not args.files:
        sys.stdout.write(run(sys.stdin.read()))
        return 0

    for path in args.files:
        with open(path, "r", encoding="utf-8") as fh:
            result = run(fh.read())
        if args.in_place:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(result)
        elif args.output:
            with open(args.output, "w", encoding="utf-8") as fh:
                fh.write(result)
        else:
            sys.stdout.write(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
