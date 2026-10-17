#!/bin/sh
# Runs the eval --direct for each vision model at its fastest reasoning level, then prints the
# comparison (eval/compare.ts). Needs AIAND_API_KEY in backend/.dev.vars.
#
#   npm run eval:models                        one model at a time, 4 photos in flight (~25 min)
#   npm run eval:models -- --parallel          all models at once, 2 photos each (~5 min). Times can
#                                              run a little high if AI& queues the extra requests.
#   npm run eval:models -- --only id,id        a few fixtures, to try it out
set -e
cd "$(dirname "$0")/.."

parallel=0
if [ "$1" = "--parallel" ]; then parallel=1; shift; fi

COMBOS="qwen/qwen3.8-27b:low
qwen/qwen3.8-27b:none
qwen/qwen3.6-27b:none
google/gemma-4-31b-it:none
deepseek-ai/deepseek-v4.1-flash:none
zai-org/glm-5.3-flash:low
moonshotai/kimi-k3:low
moonshotai/kimi-k2.7-code:high"

logs="eval/runs/logs-$(date +%Y-%m-%dT%H-%M-%S)"
mkdir -p "$logs"

for combo in $COMBOS; do
  model=${combo%%:*}; level=${combo##*:}
  log="$logs/$(echo "$model-$level" | tr '/' '_').log"
  if [ $parallel = 1 ]; then
    node eval/run.ts --direct --model "$model" --reasoning "$level" --concurrency 2 "$@" > "$log" 2>&1 &
    echo "started $model · $level"
  else
    printf "\n=== %s · %s\n" "$model" "$level"
    node eval/run.ts --direct --model "$model" --reasoning "$level" "$@" > "$log" 2>&1 || true
    tail -n 12 "$log"
  fi
done

if [ $parallel = 1 ]; then
  wait
  for log in "$logs"/*.log; do printf "\n=== %s\n" "$(basename "$log" .log)"; tail -n 12 "$log"; done
fi

printf "\n"
node eval/compare.ts
