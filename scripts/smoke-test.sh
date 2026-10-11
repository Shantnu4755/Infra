#!/bin/bash
# Smoke test through the Dwaarpal gateway (PDF 5.2, plus checks used again at go-live in 7.7).
#   scripts/smoke-test.sh                       # local: http://localhost:8080
#   scripts/smoke-test.sh https://api.<domain>  # on the server
set -euo pipefail
cd "$(dirname "$0")/.."
G="${1:-http://localhost:8080}"

ok() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; exit 1; }
expect() { [ "$2" = "$3" ] && ok "$1 ($2)" || fail "$1: expected $3, got $2"; }
field() { python3 -c "import sys, json; print(json.load(sys.stdin)$1)"; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

echo "Gateway: $G"
KEY=$(docker compose exec -T dwaarpal python -m app.cli create-key --name "smoke-$(date +%s)" --capacity 200 --refill 20)
H=(-H "X-API-Key: $KEY")
ok "API key created (printed once, ${#KEY} chars)"

expect "kavach health through the gateway" "$(curl -s "${H[@]}" "$G/api/kavach/health" | field "['status']")" "ok"
for svc in karya hisaab sutra sanjeevani; do
  expect "$svc health through the gateway" "$(code "${H[@]}" "$G/api/$svc/health")" "200"
done

POLICY=$(curl -s -X POST "${H[@]}" -H "Content-Type: application/json" \
  -d "{\"policy_number\":\"BOM-$(date +%s)\",\"holder_name\":\"Test User\",\"sum_insured\":\"500000.00\"}" \
  "$G/api/kavach/policies" | field "['data']['id']")
ok "policy created ($POLICY)"

IDEM="claim-$(date +%s)"
claim() {
  curl -s -o /tmp/smoke-claim.json -w '%{http_code}' -X POST "${H[@]}" -H "Idempotency-Key: $IDEM" \
    -H "Content-Type: application/json" \
    -d "{\"policy_id\":\"$POLICY\",\"amount\":\"25000.00\",\"description\":\"Hospital stay\"}" "$G/api/kavach/claims"
}
expect "claim submitted" "$(claim)" "201"
FIRST=$(field "['data']['id']" < /tmp/smoke-claim.json)
expect "same Idempotency-Key again returns the original" "$(claim)" "200"
expect "  ...with the same claim id" "$(field "['data']['id']" < /tmp/smoke-claim.json)" "$FIRST"
expect "approve the claim" "$(code -X POST "${H[@]}" -H 'Content-Type: application/json' -d '{}' "$G/api/kavach/claims/$FIRST/approve")" "200"
expect "illegal move APPROVED -> REJECTED" "$(code -X POST "${H[@]}" -H 'Content-Type: application/json' -d '{}' "$G/api/kavach/claims/$FIRST/reject")" "409"

expect "DELETE is rejected by MethodView" "$(code -X DELETE "${H[@]}" "$G/api/kavach/claims")" "405"
expect "no API key is a JSON 401" "$(curl -s "$G/api/kavach/health" | field "['error']['code']")" "unauthorized"
expect "unknown service" "$(code "${H[@]}" "$G/api/nowhere/x")" "404"

# Kavach's outbox relay delivers claim events to Karya, whose worker runs them.
for i in $(seq 1 30); do
  DONE=$(curl -s "${H[@]}" "$G/api/karya/jobs?task=kavach.claim_event&status=done&limit=100" \
    | python3 -c "import sys, json; print(sum(1 for j in json.load(sys.stdin)['data'] if j['payload'].get('claim_id') == '$FIRST'))")
  [ "$DONE" -ge 2 ] && break
  sleep 1
done
expect "outbox: submitted + approved events done in Karya" "$DONE" "2"

SLOW=$(docker compose exec -T dwaarpal python -m app.cli create-key --name "smoke-slow-$(date +%s)" --capacity 3 --refill 0.01)
CODES=$(for i in 1 2 3 4; do code -H "X-API-Key: $SLOW" "$G/gateway/ping"; echo -n " "; done)
expect "rate limit: 4 requests on a 3-token bucket" "$CODES" "200 200 200 429 "
expect "gateway stats are public" "$(code "$G/gateway/stats")" "200"

# Hisaab: a multipart upload through the gateway, reconciled by the worker.
printf 'txn_date,amount,reference\n2026-01-05,100.00,UTR1\n2026-01-06,"1,250.50",UTR2\n2026-01-09,75.00,ONLY-BANK\n' > /tmp/smoke-bank.csv
printf 'entry_date,amount,reference\n2026-01-05,100.00,UTR1\n2026-01-07,1250.50,LEDGER-2\n' > /tmp/smoke-ledger.csv
RUN=$(curl -s "${H[@]}" -F bank_file=@/tmp/smoke-bank.csv -F ledger_file=@/tmp/smoke-ledger.csv "$G/api/hisaab/runs" | field "['data']['id']")
for i in $(seq 1 30); do
  STATUS=$(curl -s "${H[@]}" "$G/api/hisaab/runs/$RUN" | field "['data']['status']")
  [ "$STATUS" = "DONE" ] || [ "$STATUS" = "FAILED" ] && break
  sleep 1
done
expect "hisaab run reconciled" "$STATUS" "DONE"
expect "  ...exact, fuzzy, unmatched bank, unmatched ledger" \
  "$(curl -s "${H[@]}" "$G/api/hisaab/runs/$RUN" | python3 -c "import sys, json; r = json.load(sys.stdin)['data']; print(r['matched_exact'], r['matched_fuzzy'], r['unmatched_bank'], r['unmatched_ledger'])")" \
  "1 1 1 0"

rm -f /tmp/smoke-claim.json /tmp/smoke-bank.csv /tmp/smoke-ledger.csv
echo "All smoke tests passed."
