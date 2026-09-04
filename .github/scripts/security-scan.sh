#!/usr/bin/env bash
#
# Semgrep CE security scan — same ruleset locally and in CI.
#
#   ./.github/scripts/security-scan.sh              # scan the repo
#   ./.github/scripts/security-scan.sh --canary     # prove the ruleset still detects
#   ./.github/scripts/security-scan.sh --sarif out.sarif
#
# Lives under .github/scripts/ rather than scripts/ on purpose: Foundry owns
# script/, and a sibling scripts/ directory one letter apart would be a standing
# invitation to run `forge script` against the wrong tree.
#
# Rules come from semgrep/semgrep-rules at a PINNED commit, fetched into a
# gitignored cache. Pinned rather than floating so a scan is reproducible: an
# upstream rule change can't silently alter what this gate enforces, and bumping
# RULES_SHA is a reviewable one-line diff.
#
# We fetch rather than vendor deliberately. Semgrep Rules License v1.0 permits
# use "for your own internal business purposes" but not redistribution; fetching
# at scan time is plainly use, and copying the rules into a company repo raises a
# question we don't need to answer.
set -euo pipefail

# Not `cd "$(git rev-parse ...)"` — a failure inside command substitution does not
# trip set -e, so a broken git turns into `cd ""` and the baffling error
# "cd: null directory" instead of the actual cause.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "ERROR: git cannot read this repository, so the scan cannot determine its scope." >&2
  echo "Run 'git rev-parse --show-toplevel' here to see why." >&2
  echo "In a container, this is usually 'dubious ownership' — the checkout is owned by" >&2
  echo "another user. Fix it in the job, not here (mutating global git config is not this" >&2
  echo "script's business):  git config --global --add safe.directory <workspace>" >&2
  exit 1
fi
cd "$REPO_ROOT"

RULES_SHA="40b8c63f75dc7c22c8a77482d73bfb864b146f7e"
RULES_REPO="https://github.com/semgrep/semgrep-rules.git"
# Semgrep derives rule IDs from the config path, so this directory name becomes
# part of every rule ID (e.g. semgrep-rules.solidity.security.arbitrary-...).
# `nosemgrep:` suppressions reference those full IDs — renaming this directory
# invalidates every suppression in the codebase. Not overridable for that reason.
# (It fails safe: suppressions stop matching, findings reappear, the build goes
# red — but it would be a baffling failure to debug.)
CACHE_DIR=".semgrep-rules"
# Scan the whole repo, not an allowlist of directories, so a new top-level
# directory is covered the day it is added rather than whenever someone
# remembers to update this list. Semgrep limits itself to git-tracked files, so
# out/, cache/ and broadcast/ are skipped as gitignored, and lib/ holds
# submodule gitlinks rather than tracked .sol files; EXCLUDE_DIRS below is
# belt-and-braces.
TARGETS=(.)
# Excluded from the scan, and correspondingly exempt from the coverage assertion
# at the bottom. One list feeds both so they cannot drift apart.
#
# test/ is the only judgement call here: Foundry test contracts and mocks trip
# these rules on purpose (unrestricted mint, unowned transferOwnership) and the
# noise would train people to ignore the gate. Note that semgrep's built-in
# ignore list already drops test/ silently — stating it here makes the hole
# visible instead of leaving it to an undocumented default.
EXCLUDE_DIRS=(lib test out cache broadcast)
SARIF_OUT=""
CANARY=0

# Rules the canary MUST trip, at production severity. Asserting a per-rule set
# rather than a total count, and spanning both of semgrep's matching engines:
# accessible-selfdestruct and delegatecall-to-arbitrary-address are taint-mode
# rules, the other three are pattern-mode. Taint analysis can break while
# pattern matching keeps working, so a canary made only of pattern rules would
# stay green through half a ruleset outage.
REQUIRED_RULES=(
  accessible-selfdestruct
  arbitrary-low-level-call
  delegatecall-to-arbitrary-address
  encode-packed-collision
  unrestricted-transferownership
)

while [ $# -gt 0 ]; do
  case "$1" in
    --canary) CANARY=1; shift ;;
    --sarif)  SARIF_OUT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if ! command -v semgrep >/dev/null 2>&1; then
  echo "semgrep not found. Install with: python3 -m pip install --user semgrep" >&2
  exit 127
fi

# --- fetch pinned rules -----------------------------------------------------
if [ ! -d "$CACHE_DIR/.git" ]; then
  echo "==> fetching semgrep-rules @ ${RULES_SHA:0:12}"
  rm -rf "$CACHE_DIR"
  git init -q "$CACHE_DIR"
  git -C "$CACHE_DIR" remote add origin "$RULES_REPO"
fi
if [ "$(git -C "$CACHE_DIR" rev-parse HEAD 2>/dev/null || echo none)" != "$RULES_SHA" ]; then
  git -C "$CACHE_DIR" fetch -q --depth 1 origin "$RULES_SHA"
  git -C "$CACHE_DIR" checkout -q FETCH_HEAD
fi

# --- build the ruleset ------------------------------------------------------
# EVERY security/ subdir under solidity/ — resolved by find rather than named,
# so a rule directory added upstream is picked up by the next RULES_SHA bump
# instead of needing a second edit here. best-practice/ and performance/ are
# deliberately excluded: they are style and gas rules, and this gate blocks
# merges. It is a security gate, not a linter.
CONFIGS=()
while IFS= read -r d; do CONFIGS+=(--config "$d"); done < <(
  find "$CACHE_DIR/solidity" -type d -name security | sort
)
if [ ${#CONFIGS[@]} -eq 0 ]; then
  echo "ERROR: no rule directories resolved — refusing to run an empty scan" >&2
  exit 1
fi
echo "==> $((${#CONFIGS[@]} / 2)) rule directories"   # 2 array elements per dir: --config <path>

# --- canary: prove the ruleset still detects --------------------------------
# A misconfigured ruleset reports zero findings and looks identical to clean
# code. Semgrep's Solidity support is younger than its JS/TS support, so this
# matters more here, not less: a parser or engine regression upstream would
# quietly turn this gate into a no-op. Fail loudly instead.
if [ "$CANARY" = "1" ]; then
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  # Each planted function must trip a DIFFERENT rule. selfdestruct() takes an
  # address payable, but the taint source pattern only matches a plain `address`
  # parameter — hence the parameter type plus payable() cast rather than
  # declaring `address payable target` directly, which does NOT fire.
  cat > "$TMP/Canary.sol" <<'CANARY'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract Canary {
    address public owner;

    function kill(address target) public {
        selfdestruct(payable(target));
    }

    function exec(address target, bytes calldata data) external {
        target.call(data);
    }

    function proxy(address impl, bytes calldata data) external {
        impl.delegatecall(data);
    }

    function transferOwnership(address newOwner) public {
        owner = newOwner;
    }

    function hash(string memory a, string memory b) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(a, b));
    }
}
CANARY
  echo "==> canary check (severity ERROR, matching the real scan)"
  found=$(semgrep scan "$TMP" "${CONFIGS[@]}" --severity ERROR --json --metrics off \
            --no-git-ignore 2>/dev/null \
          | python3 -c 'import json,sys; print(" ".join(sorted({r["check_id"].split(".")[-1] for r in json.load(sys.stdin)["results"]})))')
  missing=()
  for want in "${REQUIRED_RULES[@]}"; do
    case " $found " in *" $want "*) ;; *) missing+=("$want") ;; esac
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "CANARY FAILED — rules not firing: ${missing[*]}" >&2
    echo "  expected: ${REQUIRED_RULES[*]}" >&2
    echo "  got:      ${found:-<none>}" >&2
    echo "The ruleset is not detecting planted vulnerabilities. Refusing to report a clean scan." >&2
    exit 1
  fi
  echo "canary OK — all ${#REQUIRED_RULES[@]} required rules fired: $found"
  exit 0
fi

# --- scan -------------------------------------------------------------------
EXCLUDE_ARGS=()
for d in "${EXCLUDE_DIRS[@]}"; do EXCLUDE_ARGS+=(--exclude "$d"); done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
JSON_OUT="$WORK/findings.json"

ARGS=(
  scan "${TARGETS[@]}" "${CONFIGS[@]}"
  --severity ERROR
  "${EXCLUDE_ARGS[@]}"
  --exclude "$CACHE_DIR"
  --metrics off --error
  --text --json-output="$JSON_OUT"
)
if [ -n "$SARIF_OUT" ]; then ARGS+=(--sarif-output="$SARIF_OUT"); fi

echo "==> scanning ${TARGETS[*]} (blocking on ERROR)"
set +e
semgrep "${ARGS[@]}"
SCAN_STATUS=$?
set -e

# --- coverage assertion -----------------------------------------------------
# The canary proves the rules still fire; this proves they were pointed at the
# code. Two ways a file goes unscanned without anything turning red:
#
#   1. Semgrep counts a file it FAILED TO PARSE as "scanned", emits a warn-level
#      "Syntax error" and still exits 0. Verified against semgrep 1.172.0. For a
#      language whose grammar support is still maturing that is the likeliest
#      hole, and it widens every time Solidity gains syntax.
#   2. A file drops out of the target set entirely — a new gitignore entry, a
#      directory named tests/, a submodule where a source used to be.
#
# Either way the scan reports zero findings and looks exactly like clean code,
# which is the failure this whole script exists to prevent.
if [ ! -s "$JSON_OUT" ]; then
  echo "COVERAGE CHECK FAILED — semgrep produced no JSON report; cannot verify what was scanned" >&2
  exit 1
fi

EXCLUDE_RE="^($(printf '%s|' "${EXCLUDE_DIRS[@]}" | sed 's/|$//'))/"
git ls-files -- '*.sol' | grep -Ev "$EXCLUDE_RE" > "$WORK/expected.txt" || true
if [ ! -s "$WORK/expected.txt" ]; then
  echo "COVERAGE CHECK FAILED — no tracked .sol sources outside ${EXCLUDE_DIRS[*]}" >&2
  echo "Either the repo layout moved or EXCLUDE_DIRS now swallows the whole source tree." >&2
  exit 1
fi

python3 - "$JSON_OUT" "$WORK/expected.txt" <<'PY' || COVERAGE_STATUS=$?
import json, os, sys

report = json.load(open(sys.argv[1]))
expected = {line.strip() for line in open(sys.argv[2]) if line.strip()}
scanned = {os.path.relpath(p) for p in report.get("paths", {}).get("scanned", [])}

failed = False

missing = sorted(expected - scanned)
if missing:
    failed = True
    print("COVERAGE CHECK FAILED — tracked sources never scanned:", file=sys.stderr)
    for path in missing:
        print(f"  {path}", file=sys.stderr)

unparsed = sorted({e.get("path") for e in report.get("errors", []) if e.get("type") == "Syntax error"} - {None})
if unparsed:
    failed = True
    print("COVERAGE CHECK FAILED — semgrep could not parse (findings here are impossible):", file=sys.stderr)
    for path in unparsed:
        print(f"  {path}", file=sys.stderr)

if failed:
    sys.exit(1)

print(f"coverage OK — all {len(expected)} tracked .sol sources scanned and parsed")
PY
COVERAGE_STATUS=${COVERAGE_STATUS:-0}

if [ "$COVERAGE_STATUS" -ne 0 ]; then
  exit 1
fi
exit "$SCAN_STATUS"
