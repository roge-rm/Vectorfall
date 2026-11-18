#!/usr/bin/env bash
# The bots' regression check: plays a fixed set of seeded 8v8 matches on
# Ochre Fold and fails if the bots stop moving (any match with 60 s or more
# stuck) or, over all the matches together, stop attacking, defending or
# scoring: fewer than MIN_GRABS grabs, MIN_RETURNS returns or MIN_CAPTURES
# captures. Reports go to build/bot-reports/ as usual.
#
#   tools/bot-check.sh
set -uo pipefail

cd "$(dirname "$0")/.."
SEEDS="1 2 3 4"
MINUTES=4
MIN_GRABS=12
MIN_RETURNS=8
MIN_CAPTURES=1
status=0
grabs=0
returns=0
captures=0
for seed in $SEEDS; do
	out=$(tools/bot-match.sh --bots 8 --seed "$seed" --minutes "$MINUTES" --check)
	code=$?
	line=$(echo "$out" | grep "^CHECK")
	echo "${line:-CHECK FAIL seed $seed: no result}"
	if [ $code -ne 0 ] || [ -z "$line" ]; then
		status=1
		continue
	fi
	captures=$((captures + $(echo "$line" | sed -n 's/.*: \([0-9]*\) captures.*/\1/p')))
	grabs=$((grabs + $(echo "$line" | sed -n 's/.* \([0-9]*\) grabs.*/\1/p')))
	returns=$((returns + $(echo "$line" | sed -n 's/.* \([0-9]*\) returns.*/\1/p')))
done
for want in "grabs $grabs $MIN_GRABS" "returns $returns $MIN_RETURNS" "captures $captures $MIN_CAPTURES"; do
	set -- $want
	if [ "$2" -lt "$3" ]; then
		echo "FAIL: $2 $1 in all, under $3"
		status=1
	fi
done
echo "Bot check: $captures captures, $grabs grabs, $returns returns over seeds $SEEDS, $([ $status -eq 0 ] && echo passed || echo failed)"
exit $status
