# bend-semver-checks

API-breakage detector for Bend 2 `LAWS.bend` files, written in Bend.

In a law-driven Bend project, `LAWS.bend` states the contract and `PROOF.bend`
proves it. If a law disappears or its statement changes, downstream code that
relied on it is silently broken. `bend-semver-checks` lists the laws of a file and
diffs two versions of it (two files, or a git ref against the working tree).

Pinned to Bend **2.0.38** (`.bend-version`).

## Usage

```
bend-semver-checks list <LAWS.bend>
bend-semver-checks list --git <ref> <LAWS.bend>
bend-semver-checks diff <old LAWS.bend> <new LAWS.bend>
bend-semver-checks diff --git <ref> <LAWS.bend>
bend-semver-checks --version | --help
```

`--git <ref>` reads the old side with `git show <ref>:./<file>`, run
(`Process.run`, no shell) in the file's own directory, so the path may be
relative or absolute and need not be at the repository root. The new side is the
file in the working tree. A `<ref>` starting with `-` is refused (git would read
it as an option).

### Exit codes

| code | meaning |
|---|---|
| 0 | `list` ok; `diff` found nothing removed or changed (additions only, or identical) |
| 1 | `diff` found a law removed or changed (breaking) |
| 2 | usage error, unreadable file, `git show` failure, or a LAWS.bend that does not parse |

Errors go to stderr as one line (`path:line: message`); JSON goes to stdout.

### `list`

```
$ bend-semver-checks list LAWS.bend
{"file":"LAWS.bend","laws":[{"name":"add_zero","line":5,"binders":["for x: Nat"],"statement":"{Nat.add(x, 0n) == x : Nat}"}]}
```

`binders` are the `for` / `exs` lines in order; `statement` is the rest of the
law. Both are whitespace-normalised and comment-free.

### `diff`

```
$ bend-semver-checks diff --git v1 LAWS.bend
{"old":"v1:LAWS.bend","new":"LAWS.bend","breaking":true,
 "summary":{"removed":1,"changed":1,"added":0,"unchanged":3},
 "removed":[{"name":..,"line":..,"binders":[..],"statement":".."}],
 "changed":[{"name":"add_zero","kind":"weakened","old":{..},"new":{..}}],
 "added":[]}
```

(One line of JSON in reality.) Laws are matched by name.

| bucket | meaning | breaking |
|---|---|---|
| `removed` | a law of the old file has no law of that name in the new one | yes |
| `changed` | same name, different binders or statement | yes |
| `added` | a law only in the new file | no |

`changed.kind` is a hint about direction, decided from binders only:

- `weakened`: statement identical and the new binders are the old ones plus extra
  ones (a premise was added, so the law claims less).
- `strengthened`: statement identical and binders were dropped.
- `changed`: anything else, including every statement edit.

Whether an edited statement is weaker or stronger is a question about types and
proofs; this tool does not try to answer it, so every statement edit is
reported as `changed`. A `strengthened` law is still exit 1: its `PROOF.bend`
def no longer matches. Read `kind` if you want to treat it differently. A renamed
law shows as one removal plus one addition.

## How laws are read

A purpose-built, line-based extractor (`src/law.bend`), not a full Bend parser:

- a law starts at a `law name:` line at column 0 and runs until the next
  non-blank, non-indented line;
- lines starting `for ` or `exs ` are binders, all other lines are the statement;
- `#` comments are dropped and whitespace runs collapse to one space, except
  inside string and char literals (so a change inside a string literal counts);
- a line continues onto the next while a bracket is open or it ends in `->`, so
  binders and statements may wrap;
- a malformed header (`law name` with no colon), a law with no statement, or a
  duplicate law name is a parse error (exit 2).

Comparison is textual after that normalisation. Renaming a binder, or any other
alpha-equivalent rewrite, is reported as a change.

### Why not bolt's outline parser?

The plan was to import `src/syntax/outline.bend` from bolt on the hub. It does
check on Bend 2.0.38 (bolt as a whole fails there: its `Text` constructor
collides with Base's new `Text` event). I wrote the extractor myself anyway: it
removes a network and hub-hash dependency from the build, avoids an upstream
fork, and the law surface needed here is small. Nothing from bolt is vendored.
Cross-check: on the 8 `LAWS.bend` files in bolt's tree (133 laws in
`src/rules/LAWS.bend` alone) the extracted names equal `grep '^law '`.

## Build and test

Needs `bend` 2.0.38 on `PATH` (clang 14+), `just`, and `jq`, `sed`, `git` for the tests.

```
just build     # native binary at bin/bend-semver-checks (via `bend main.bend -o`)
just test      # build + golden tests (stdout, stderr, exit code)
just update-goldens   # rewrite tests/golden after an intended output change
just ci        # version pin check, pin-gate self-test, typecheck + --verdict, build, test
```

`just ci` fails when `bend version` differs from `.bend-version`. Update the pin
and the goldens together when upgrading Bend: `UPDATE=1 sh tests/run.sh`, then
review the diff.

Tests live in `tests/run.sh` with fixtures in `tests/fixtures/` and expected
output in `tests/golden/`. Git cases run in a throwaway repository.

## Bend notes

Things that cost iterations, for the next person: variables are affine (write
`+x` to reuse); `match` cannot scrutinise a computed value (pass it to a helper
def); defs must be written above their callers and mutual recursion is refused,
so the scanners are single loops over a state record with non-recursive
transition functions; `Type`-kinded values (pairs, `File`, closures) cannot sit
in a `&2` container, so small `Data` records stand in for tuples.

## License

MIT, see `LICENSE`.
