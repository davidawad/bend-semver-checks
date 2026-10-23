import Base
import ./src/text.bend as T
import ./src/law.bend as L
import ./src/diff.bend as D

# bend-semver-checks: list the laws of a LAWS.bend and detect API breakage between two.
#
#   bend-semver-checks list <LAWS.bend>
#   bend-semver-checks list --git <ref> <LAWS.bend>
#   bend-semver-checks diff <old LAWS.bend> <new LAWS.bend>
#   bend-semver-checks diff --git <ref> <LAWS.bend>
#
# Exit codes: 0 ok (diff: nothing removed or changed), 1 breaking diff,
# 2 usage, I/O, git or parse error.

def version() -> String:
  "bend-semver-checks 0.1.0"

def usage() -> String:
  "usage:\n  bend-semver-checks list <LAWS.bend>\n  bend-semver-checks list --git <ref> <LAWS.bend>\n  bend-semver-checks diff <old LAWS.bend> <new LAWS.bend>\n  bend-semver-checks diff --git <ref> <LAWS.bend>\n  bend-semver-checks --version | --help\n\nexit: 0 ok, 1 breaking change (law removed or changed), 2 usage or parse error"

# 64 MB: far above any LAWS.bend.
def max_bytes() -> U32:
  64000000

def die(+msg: String) -> IO(Unit):
  IO.die(Unit, 2, msg)

def done() -> IO(Unit):
  IO.pure(Unit, Unit{})

# --- reading text ---------------------------------------------------------------

def after_read(+path: String, r: File & Result<&1, &1, U32 & String, String>, k: String -> IO(Unit)) -> IO(Unit):
  match r:
    case (f, Done{text}):
      do IO<Unit>:
        File.close(f)
        k(text)
    case (f, Fail{(code, msg)}):
      die("cannot read " ++ path ++ ": " ++ msg)

def after_open(+path: String, r: Result<&1, &1, U32 & String, File>, k: String -> IO(Unit)) -> IO(Unit):
  match r:
    case Done{f}:
      do IO<Unit>:
        r2 : File & Result<&1, &1, U32 & String, String> <- File.read(f, max_bytes())
        after_read(path, r2, k)
    case Fail{(code, msg)}:
      die("cannot open " ++ path ++ ": " ++ msg)

# Read a file, then continue with its text.
def load_file(+path: String, k: String -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    after_open(path, r, k)

type Path is Data:
  Path{dir: String, base: String}

def dir.fix(+blank: Bool, +dir: String, +base: String) -> Path:
  match blank:
    case True{}:
      Path{"/", base}
    case False{}:
      Path{dir, base}

# Split at the last slash: "a/b/LAWS.bend" -> ("a/b", "LAWS.bend"), "LAWS.bend" -> (".", "LAWS.bend").
def split_rev(+r: String, +base: String) -> Path:
  match r:
    case SNil{}:
      Path{".", base}
    case SCon{c, t}:
      match c:
        case '/':
          dir.fix(T.blank(t), String.reverse(t), base)
        case _:
          split_rev(t, SCon{c, base})

def split_path(+path: String) -> Path:
  split_rev(String.reverse(path), SNil{})

def git_done(+ok: Bool, +ref: String, +path: String, +out: String, +err: String, k: String -> IO(Unit)) -> IO(Unit):
  match ok:
    case True{}:
      k(out)
    case False{}:
      die("git show " ++ ref ++ ":" ++ path ++ " failed: " ++ String.trim(err))

def after_git(+ref: String, +path: String, r: Result<&1, &1, U32 & String, U32 & (String & String)>, k: String -> IO(Unit)) -> IO(Unit):
  match r:
    case Done{(status, (out, err))}:
      git_done(U32.is_eq(status, 0), ref, path, out, err, k)
    case Fail{(code, msg)}:
      die("cannot run git: " ++ msg)

def run_git(+ref: String, +path: String, +p: Path, k: String -> IO(Unit)) -> IO(Unit):
  match p:
    case Path{dir, base}:
      do IO<Unit>:
        r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("git", ["-C", dir, "show", ref ++ ":./" ++ base], "", max_bytes(), 30000)
        after_git(ref, path, r, k)

# The text of a file as of a git ref (`git show <ref>:./<file>` in the file's directory).
def load_git(+ref: String, +path: String, k: String -> IO(Unit)) -> IO(Unit):
  run_git(ref, path, split_path(path), k)

# --- commands -------------------------------------------------------------------------

def parse_fail(+label: String, +line: U32, +msg: String) -> IO(Unit):
  die(label ++ ":" ++ U32.show(line) ++ ": " ++ msg)

def list_text(+label: String, +p: L.Parsed) -> IO(Unit):
  match p:
    case L.Good{ls}:
      IO.print("{\"file\":" ++ T.jstr(label) ++ ",\"laws\":" ++ L.laws_json(ls) ++ "}")
    case L.Bad{line, msg}:
      parse_fail(label, line, msg)

def exit_if(+brk: Bool) -> IO(Unit):
  match brk:
    case True{}:
      IO.exit(1)
    case False{}:
      done()

def emit(+json: String, +brk: Bool) -> IO(Unit):
  do IO<Unit>:
    IO.print(json)
    exit_if(brk)

def diff_new(+ol: String, +nl: String, +a: List<&2, L.Law>, +q: L.Parsed) -> IO(Unit):
  match q:
    case L.Good{b}:
      emit(D.report(ol, nl, a, b), D.breaking(a, b))
    case L.Bad{line, msg}:
      parse_fail(nl, line, msg)

def diff_old(+ol: String, +nl: String, +p: L.Parsed, +newtext: String) -> IO(Unit):
  match p:
    case L.Good{a}:
      diff_new(ol, nl, a, L.parse(newtext))
    case L.Bad{line, msg}:
      parse_fail(ol, line, msg)

def diff_texts(+ol: String, +nl: String, +oldtext: String, +newtext: String) -> IO(Unit):
  diff_old(ol, nl, L.parse(oldtext), newtext)

def list_file(+path: String) -> IO(Unit):
  load_file(path, text => list_text(path, L.parse(text)))

def list_git(+ref: String, +path: String) -> IO(Unit):
  load_git(ref, path, text => list_text(ref ++ ":" ++ path, L.parse(text)))

def diff_files(+old: String, +new: String) -> IO(Unit):
  load_file(old, oldtext => load_file(new, newtext => diff_texts(old, new, oldtext, newtext)))

def diff_git(+ref: String, +path: String) -> IO(Unit):
  load_git(ref, path, oldtext => load_file(path, newtext => diff_texts(ref ++ ":" ++ path, path, oldtext, newtext)))

# --- argument dispatch ---------------------------------------------------------------------

def bad_usage() -> IO(Unit):
  die(usage())

# A ref that starts with `-` would be read by git as an option.
def ref_ok(+ref: String) -> Bool:
  Bool.not(String.starts_with(ref, "-"))

def with_ref(+ok: Bool, +ref: String, f: String -> IO(Unit)) -> IO(Unit):
  match ok:
    case True{}:
      f(ref)
    case False{}:
      bad_usage()

def list3(+is_git: Bool, +ref: String, +path: String) -> IO(Unit):
  match is_git:
    case True{}:
      with_ref(ref_ok(ref), ref, r => list_git(r, path))
    case False{}:
      bad_usage()

def diff3(+is_git: Bool, +ref: String, +path: String) -> IO(Unit):
  match is_git:
    case True{}:
      with_ref(ref_ok(ref), ref, r => diff_git(r, path))
    case False{}:
      bad_usage()

def list_args(rest: List<String>) -> IO(Unit):
  match rest:
    case Con{a, Nil{}}:
      list_file(a)
    case Con{g, Con{ref, Con{path, Nil{}}}}:
      list3(String.eq(g, "--git"), ref, path)
    case _:
      bad_usage()

def diff_args(rest: List<String>) -> IO(Unit):
  match rest:
    case Con{a, Con{b, Nil{}}}:
      diff_files(a, b)
    case Con{g, Con{ref, Con{path, Nil{}}}}:
      diff3(String.eq(g, "--git"), ref, path)
    case _:
      bad_usage()

def route(+is_list: Bool, +is_diff: Bool, +is_help: Bool, +is_version: Bool, rest: List<String>) -> IO(Unit):
  match is_list:
    case True{}:
      list_args(rest)
    case False{}:
      match is_diff:
        case True{}:
          diff_args(rest)
        case False{}:
          match is_help:
            case True{}:
              IO.print(usage())
            case False{}:
              match is_version:
                case True{}:
                  IO.print(version())
                case False{}:
                  bad_usage()

def command(+c: String, rest: List<String>) -> IO(Unit):
  route(String.eq(c, "list"), String.eq(c, "diff"), Bool.or(String.eq(c, "--help"), Bool.or(String.eq(c, "-h"), String.eq(c, "help"))), String.eq(c, "--version"), rest)

def dispatch(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{c, rest}}:
      command(c, rest)
    case _:
      bad_usage()

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch(args)
