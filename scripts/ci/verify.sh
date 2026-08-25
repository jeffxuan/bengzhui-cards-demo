#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
SIMULATION_MATCHES="${SIMULATION_MATCHES:-1000}"
LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$LOG_DIR"' EXIT

if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [[ ! -x "$GODOT_BIN" ]]; then
  if [[ "$(uname -s)" == "Darwin" && -x "/Users/jeff.jiang/Desktop/Godot.app/Contents/MacOS/Godot" ]]; then
    GODOT_BIN="/Users/jeff.jiang/Desktop/Godot.app/Contents/MacOS/Godot"
  fi
fi
if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [[ ! -x "$GODOT_BIN" ]]; then
  echo "Godot executable not found: $GODOT_BIN" >&2
  exit 1
fi

run_check() {
  local name="$1"
  local marker="$2"
  shift 2
  local log_file="$LOG_DIR/$name.log"

  echo "==> $name"
  if ! "$GODOT_BIN" --headless --path "$ROOT_DIR" "$@" 2>&1 | tee "$log_file"; then
    echo "$name failed with a non-zero exit code." >&2
    exit 1
  fi
  if rg -n 'SCRIPT ERROR|Parse Error|ERROR:|WARNING:|Failed loading resource' "$log_file"; then
    echo "$name emitted an error or warning." >&2
    exit 1
  fi
  if [[ -n "$marker" ]] && ! rg -Fq "$marker" "$log_file"; then
    echo "$name did not emit required marker: $marker" >&2
    exit 1
  fi
}

run_check compile "" --editor --quit
run_check rules RULE_TESTS_OK --script res://tests/run_rules_tests.gd
run_check saves SAVE_TESTS_OK --script res://tests/run_save_tests.gd
run_check ui UI_SMOKE_OK --script res://tests/run_ui_smoke.gd
run_check export-smoke EXPORT_SMOKE_OK -- --export-smoke
run_check simulation SIMULATION_OK --script res://tests/run_simulation.gd -- --matches="$SIMULATION_MATCHES"

echo "VERIFY_OK: compile, rules, saves, UI, export smoke, and $SIMULATION_MATCHES simulations passed."
