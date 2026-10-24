# Showcase

All renders come from the generic sample files in `docs/showcase/sample/`.
Regenerate everything with:

```
just build
docs/showcase/make-screenshots.sh
```

Needs `jq` and a headless Chrome (`CHROME=/path/to/chrome` overrides the macOS default).

## diff.png

`bend-semver-checks diff docs/showcase/sample/LAWS.old.bend docs/showcase/sample/LAWS.new.bend`,
rendered as a terminal-style image. The old file has `add_zero`, `add_comm` and
`mul_one`; the new one drops `add_comm`, adds a premise to `add_zero` (weakened)
and adds `mul_zero`. Exit code 1 (breaking).
