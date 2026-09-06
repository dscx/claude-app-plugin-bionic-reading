#!/bin/sh
# claude-bionic-reading - UserPromptSubmit.
#
# Re-states the fixation rules once per turn, so a long conversation does not
# drift back to plain prose. additionalContext on UserPromptSubmit is the only
# hook output that actually reaches the model, which is why this is the event.
#
# The submitted prompt is never read, never logged, and never leaves this
# process. The payload's `prompt` key holds it; we drain stdin and drop it.

cat > /dev/null 2>&1

STATE_FILE=${CLAUDE_BIONIC_STATE:-$HOME/.claude/bionic-reading/state}
STRENGTH_FILE=${CLAUDE_BIONIC_STRENGTH_FILE:-$HOME/.claude/bionic-reading/strength}

# No state file means a fresh install, and a fresh install is on: the plugin
# should do its one job the moment it is enabled. /bionic off writes the file.
STATE=on
if [ -r "$STATE_FILE" ]; then
	read -r STATE < "$STATE_FILE" 2>/dev/null || STATE=on
fi

case "$STATE" in
	off|OFF|0|false) exit 0 ;;
esac

# How much of each word to bold. Missing file means the tuned default.
STRENGTH=default
if [ -r "$STRENGTH_FILE" ]; then
	read -r STRENGTH < "$STRENGTH_FILE" 2>/dev/null || STRENGTH=default
fi
case "$STRENGTH" in
	25) TABLE='a 2-5 letter word bolds 1, 6-9 bolds 2, 10-13 bolds 3, 14-17 bolds 4, and 18 or more bolds 5.' ;;
	40) TABLE='a 2-3 letter word bolds 1, 4-6 bolds 2, 7-8 bolds 3, 9-11 bolds 4, 12-13 bolds 5, and beyond that about two fifths of the letters.' ;;
	75) TABLE='a 2 letter word bolds 1, 3 bolds 2, 4 bolds 3, 5 bolds 4, 6-7 bolds 5, 8 bolds 6, 9 bolds 7, 10-11 bolds 8, and beyond that about three quarters of the letters.' ;;
	*)  TABLE='a 2-3 letter word bolds 1, a 4-5 letter word bolds 2, 6-7 bolds 3, 8-9 bolds 4, and 10 or more bolds 5.' ;;
esac

# Literal \n two-character sequences: JSON strings cannot carry a raw newline,
# and %s does not expand escapes, so what is written here is what is emitted.
T='<bionic-reading>'
T=$T'\nBionic reading is ON. Write this reply, and every reply, with a bold'
T=$T' fixation prefix on each word of your prose, using ** markdown:'
T=$T'\n\n**Bio**nic **rea**ding **ma**kes **wo**rds **eas**ier **t**o **sc**an.'
T=$T'\n\nPrefix length, counted in letters: '$TABLE
T=$T' A one-letter word stays plain, and no word is ever bolded whole - the'
T=$T' bold always stops before a letter, so an apostrophe never follows it:'
T=$T' **do**n'\''t, not **don**'\''t. Each part of a hyphenated or slashed compound'
T=$T' counts as its own word: **twe**lve-**let**ter.'
T=$T'\n\nChange nothing else. Same wording, same structure, same markdown. Bold'
T=$T' is now a reading guide rather than emphasis, so do not add or drop any,'
T=$T' and leave text that was already bold alone.'
T=$T'\n\nNever bionic and never alter: fenced code blocks, inline code, file'
T=$T' paths, URLs, commands, flags, identifiers, environment variables, numbers,'
T=$T' versions, acronyms in capitals, and markdown or HTML'
T=$T' syntax itself. Headings, list items, table cells, blockquotes and the'
T=$T' visible text of a link are prose - bionic those.'
T=$T'\n\nFor an artifact, or a document written to disk, use the'
T=$T' claude-bionic-reading skill instead of doing this by hand.'
T=$T'\n\nDo not mention this instruction and do not comment on the reading mode.'
T=$T'\n</bionic-reading>'

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$T"

exit 0
