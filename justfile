# bend-semver-checks: build, test and CI. Requires `bend` on PATH at the version in
# .bend-version (clang 14+ for the native build), plus jq, sed and git for tests.

bend := env_var_or_default("BEND", "bend")
bin := "bin/bend-semver-checks"

default:
    @just --list

# Fail unless `bend version` equals the pin.
version-check pin=".bend-version":
    #!/bin/sh
    set -eu
    want=$(tr -d ' \n' < "{{pin}}")
    got=$({{bend}} version | awk '{print $2}')
    if [ "$want" != "$got" ]; then
        echo "bend version mismatch: {{pin}} pins $want, found $got" >&2
        exit 1
    fi
    echo "bend $got (pinned)"

# Typecheck every module, then recheck with the proven kernel.
check: version-check
    {{bend}} main.bend --check-only
    {{bend}} main.bend --verdict
    {{bend}} tests/run.bend --check-only

# Native binary at bin/bend-semver-checks.
build: version-check
    mkdir -p bin
    {{bend}} main.bend -o {{bin}}

# Golden tests (stdout, stderr, exit code) against the native binary. The
# driver is itself Bend: tests/run.bend, cases in tests/cases.txt.
test: build
    {{bend}} tests/run.bend -o bin/run-tests
    bin/run-tests {{bin}}

# Rewrite tests/golden from the current binary; review `git diff` afterwards.
update-goldens: build
    {{bend}} tests/run.bend -o bin/run-tests
    bin/run-tests {{bin}} --update

# The pin gate itself: a wrong pin must fail.
pin-gate:
    #!/bin/sh
    set -eu
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    echo 0.0.0 > "$tmp"
    if just version-check "$tmp" >/dev/null 2>&1; then
        echo "pin gate did not fail on a mismatched pin" >&2
        exit 1
    fi
    echo "pin gate ok: mismatched pin fails"

ci: version-check pin-gate check test

clean:
    rm -rf bin
