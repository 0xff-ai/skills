#!/usr/bin/env bash
# Fork-session eval harness for the fable-5-emulation skill.
#
# Loads the skill once into a base session, then forks that base per eval:
# `claude -p --resume <base> --fork-session` branches a fresh session id from
# the base for each case, so the skill is loaded once (not re-sent from scratch
# per case) and the base is never mutated. Each fork is an isolated Opus session
# governed only by the skill, with tools disabled.
#
# Prompts live in evals/prompts/EVAL-NN.txt and mirror the cases in EVALS.md.
# Outputs go to a fresh temp dir (printed at the end); nothing is written back
# into the repo. The em-dash and postamble counts are the cheap mechanical
# checks; read the output files for the judge rubrics in EVALS.md.
#
# Usage:
#   evals/run.sh            # run all cases
#   evals/run.sh 10 19      # run specific cases
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$DIR/../skills/fable-5-emulation/SKILL.md"
P="$DIR/prompts"
OUT="$(mktemp -d -t fable-evals-XXXX)"
NOTOOLS=(--disallowed-tools Bash Edit Write Read Glob Grep WebFetch WebSearch Task NotebookEdit)

echo "skill: $SKILL"
echo "out:   $OUT"

# 1. Base session: load the skill exactly once.
BASE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
echo "base:  $BASE_ID"
{
  echo "Adopt the behavioral skill below as the rules for this whole session. For every message I send after this one, reply exactly as you would to a real user under these rules: from your own knowledge, do not use tools, output only your reply. Acknowledge THIS message with just the single word: ready"
  echo
  cat "$SKILL"
} | claude -p --session-id "$BASE_ID" --model opus "${NOTOOLS[@]}" \
    --output-format text > "$OUT/_base_ack.txt" 2>&1
echo "ack:   $(cat "$OUT/_base_ack.txt")"

# 2. Fork the base once per eval.
EVALS=("$@")
if [ ${#EVALS[@]} -eq 0 ]; then
  EVALS=()
  for f in "$P"/EVAL-*.txt; do
    b="$(basename "$f")"; b="${b#EVAL-}"; EVALS+=("${b%.txt}")
  done
fi

for n in "${EVALS[@]}"; do
  claude -p --resume "$BASE_ID" --fork-session --model opus "${NOTOOLS[@]}" \
    --output-format text < "$P/EVAL-$n.txt" > "$OUT/EVAL-$n.txt" 2>&1
  echo "done EVAL-$n  emdash=$(grep -c '—' "$OUT/EVAL-$n.txt")  postamble=$(grep -ciE '(want me to|let me know if|feel free|happy to (help|assist|elaborate|expand))' "$OUT/EVAL-$n.txt")  ($(wc -c < "$OUT/EVAL-$n.txt") B)"
done
echo "ALL DONE -> $OUT"
