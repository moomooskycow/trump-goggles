#!/bin/bash

# verify-ci.sh - Local CI verification script
# Runs the same quality checks as the GitHub Actions CI workflow.

set -u -o pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED_CHECKS=()

run_check() {
  local label="$1"
  shift

  echo -e "${YELLOW}Running ${label}...${NC}"
  if "$@"; then
    echo -e "${GREEN}✓ ${label} passed${NC}"
  else
    echo -e "${RED}✗ ${label} failed${NC}"
    FAILED_CHECKS+=("${label}")
  fi
  echo
}

validate_structured_logs() {
  local temp_log_file
  local extracted_logs
  temp_log_file="$(mktemp)"
  extracted_logs="$(mktemp)"

  echo "Running CI log validation test..."
  if ! pnpm test test/utils/logger-ci-validation.test.ts --reporter=verbose 2>&1 | tee "$temp_log_file"; then
    rm -f "$temp_log_file" "$extracted_logs"
    return 1
  fi

  echo "Extracting structured logs from test output..."
  grep -E '\{.*"timestamp".*"level".*"service_name".*"correlation_id".*"function_name".*"component".*\}' "$temp_log_file" > "$extracted_logs" || true

  if [ ! -s "$extracted_logs" ]; then
    echo "No structured logs found in test output."
    echo "=== Full test output preview ==="
    head -50 "$temp_log_file"
    echo "=== End of test output preview ==="
    rm -f "$temp_log_file" "$extracted_logs"
    return 1
  fi

  echo "Sample extracted logs:"
  head -3 "$extracted_logs"
  echo "..."
  pnpm dlx tsx scripts/validate-logs.ts "$extracted_logs"
  local status=$?

  rm -f "$temp_log_file" "$extracted_logs"
  return "$status"
}

echo -e "${YELLOW}===== Trump Goggles CI Verification =====${NC}"
echo "Running checks to verify CI compliance..."
echo

run_check "ESLint" pnpm lint
run_check "TypeScript" pnpm typecheck
run_check "tests" pnpm test
run_check "test coverage" pnpm test:coverage
run_check "build" pnpm build
run_check "structured log validation" validate_structured_logs

echo -e "${YELLOW}===== Verification Results =====${NC}"
if [ "${#FAILED_CHECKS[@]}" -eq 0 ]; then
  echo -e "${GREEN}All CI checks passed. Your changes should pass CI.${NC}"
  exit 0
fi

echo -e "${RED}Some CI checks failed. Please fix the issues before pushing.${NC}"
echo "Failed checks:"
for check in "${FAILED_CHECKS[@]}"; do
  echo -e "${RED}  ✗ ${check}${NC}"
done
exit 1
