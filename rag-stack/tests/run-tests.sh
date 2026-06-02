#!/usr/bin/env bash
# run-tests.sh — run Go unit tests for all services, then E2E tests on hierophant
#
# Usage:
#   bash run-tests.sh              # unit tests + E2E
#   bash run-tests.sh --unit-only  # unit tests only (no cluster required)
#   bash run-tests.sh --e2e-only   # E2E only (skip unit tests)
#   bash run-tests.sh --fail-fast  # stop at first unit test failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="${SCRIPT_DIR}/../services"

UNIT_ONLY=false
E2E_ONLY=false
FAIL_FAST=false

for arg in "$@"; do
  case "$arg" in
    --unit-only)  UNIT_ONLY=true ;;
    --e2e-only)   E2E_ONLY=true ;;
    --fail-fast)  FAIL_FAST=true ;;
    *) echo "[ERROR] Unknown argument: $arg"; exit 1 ;;
  esac
done

# ──────────────────────────────────────────────────────────────────────────────
# Go unit tests
# ──────────────────────────────────────────────────────────────────────────────

# All modules — vet runs on all, test only on those with *_test.go files
ALL_MODULES=(
  common
  build-orchestrator
  db-adapter
  llm-gateway
  memory-controller
  object-store-mgr
  prompt-aggregator
  qdrant-adapter
  rag-admin-api
  rag-worker
)

MODULES_WITH_TESTS=(
  common
  db-adapter
  llm-gateway
  memory-controller
  prompt-aggregator
  qdrant-adapter
  rag-admin-api
  rag-worker
)

run_unit_tests() {
  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "  Go Unit Tests"
  echo "════════════════════════════════════════════════════════"

  declare -A VET_RESULTS
  declare -A TEST_RESULTS

  # go vet — all modules
  echo ""
  echo "── go vet ──────────────────────────────────────────────"
  for mod in "${ALL_MODULES[@]}"; do
    dir="${SERVICES_DIR}/${mod}"
    if [ ! -f "${dir}/go.mod" ]; then
      printf "  vet  %-32s SKIP\n" "${mod}"
      VET_RESULTS[$mod]="SKIP"
      continue
    fi
    printf "  vet  %-32s" "${mod}"
    if output=$(cd "$dir" && go vet ./... 2>&1); then
      echo " OK"
      VET_RESULTS[$mod]="OK"
    else
      echo " FAIL"
      echo "$output" | sed 's/^/         /'
      VET_RESULTS[$mod]="FAIL"
    fi
  done

  # go test — modules with test files
  echo ""
  echo "── go test ─────────────────────────────────────────────"
  for mod in "${MODULES_WITH_TESTS[@]}"; do
    dir="${SERVICES_DIR}/${mod}"
    printf "  test %-32s" "${mod}"
    if output=$(cd "$dir" && go test ./... 2>&1); then
      echo " OK"
      TEST_RESULTS[$mod]="OK"
    else
      echo " FAIL"
      echo "$output" | sed 's/^/         /'
      TEST_RESULTS[$mod]="FAIL"
      if $FAIL_FAST; then
        echo ""
        echo "[FAIL-FAST] Stopping after first test failure."
        return 1
      fi
    fi
  done

  # Summary
  echo ""
  echo "── Summary ─────────────────────────────────────────────"
  local unit_failures=0

  echo "  Vet:"
  for mod in "${ALL_MODULES[@]}"; do
    r="${VET_RESULTS[$mod]:-SKIP}"
    printf "    %-32s %s\n" "${mod}" "$r"
    [[ "$r" == "FAIL" ]] && unit_failures=$((unit_failures + 1))
  done

  echo "  Test:"
  for mod in "${MODULES_WITH_TESTS[@]}"; do
    r="${TEST_RESULTS[$mod]:-SKIP}"
    printf "    %-32s %s\n" "${mod}" "$r"
    [[ "$r" == "FAIL" ]] && unit_failures=$((unit_failures + 1))
  done

  if [ "$unit_failures" -eq 0 ]; then
    echo ""
    echo "  [OK] All unit tests passed."
    return 0
  else
    echo ""
    echo "  [FAILURE] ${unit_failures} module(s) failed."
    return 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────────────────────────────────────

UNIT_EXIT=0
E2E_EXIT=0

if ! $E2E_ONLY; then
  run_unit_tests || UNIT_EXIT=$?
fi

if ! $UNIT_ONLY; then
  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "  E2E Tests"
  echo "════════════════════════════════════════════════════════"
  echo ""
  bash "${SCRIPT_DIR}/run-e2e-on-hierophant.sh" || E2E_EXIT=$?
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  Final Result"
echo "════════════════════════════════════════════════════════"

if ! $E2E_ONLY; then
  [ "$UNIT_EXIT" -eq 0 ] && echo "  Unit tests : PASS" || echo "  Unit tests : FAIL"
fi
if ! $UNIT_ONLY; then
  [ "$E2E_EXIT" -eq 0 ] && echo "  E2E tests  : PASS" || echo "  E2E tests  : FAIL"
fi

[ "$((UNIT_EXIT + E2E_EXIT))" -eq 0 ] && exit 0 || exit 1
