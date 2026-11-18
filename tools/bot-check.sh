#!/usr/bin/env bash
# The bots' regression check: plays a fixed set of seeded 8v8 matches on
# Ochre Fold and fails if the bots stop attacking, defending or moving (each
# match needs 2 grabs, a return and under 60 s stuck), or if none of them
# captures. Reports go to build/bot-reports/ as usual.
#
#   tools/bot-check.sh
set -uo pipefail

cd "$(dirname "$0")/.."
SEEDS="1 2 3"
MINUTES=4
status=0
captures=0
for seed in $SEEDS; do
	out=$(tools/bot-match.sh --bots 8 --seed "$seed" --minutes "$MINUTES" --check)
	code=$?
	line=$(echo "$out" | grep "^CHECK")
	echo "${line:-CHECK FAIL seed $seed: no result}"
	if [ $code -ne 0 ] || [ -z "$line" ]; then
		status=1
	fi
	captures=$((captures + $(echo "$line" | sed -n 's/.*: \([0-9]*\) captures.*/\1/p')))
done
if [ "$captures" -lt 1 ]; then
	echo "FAIL: no captures in any match"
	status=1
fi
echo "Bot check: $captures captures over seeds $SEEDS, $([ $status -eq 0 ] && echo passed || echo failed)"
exit $status
