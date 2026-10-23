import Base
import ../src/text.bend as T

# Golden-test driver for bend-laws, written in Bend (no shell).
#
#   run-tests <path to bend-laws> [--update]
#
# Run from the repository root. Reads tests/cases.txt; each case line is
#   name want_exit arg...        (@ABS@ at the start of an arg = absolute repo root)
#   absent name path             (the file at path must not exist)
# and compares the binary's stdout, stderr and exit code against
# tests/golden/<name>.out, .err. The absolute root is masked as <root>.
# A throwaway git repository is built under tests/.tmp-repo for the --git cases.
# --update rewrites the goldens (review the diff).

def max_bytes() -> U32:
  64000000






def repo() -> String:
  "tests/.tmp-repo"






def die(+msg: String) -> IO(Unit):
  IO.die(Unit, 2, msg)






def done() -> IO(Unit):
  IO.pure(Unit, Unit{})






# --- files ------------------------------------------------------------------------

def read_g.close(+t: String, f: File) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    File.close(f)
    return Some{t}






def read_g.none(f: File) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    File.close(f)
    return None{}






def read_g.read(r: File & Result<&1, &1, U32 & String, String>) -> IO(Maybe<&2, String>):
  match r:
    case (f, Done{t}):
      read_g.close(t, f)
    case (f, Fail{e}):
      read_g.none(f)






def read_g.open(r: Result<&1, &1, U32 & String, File>) -> IO(Maybe<&2, String>):
  match r:
    case Done{f}:
      do IO<Maybe<&2, String>>:
        r2 : File & Result<&1, &1, U32 & String, String> <- File.read(f, max_bytes())
        read_g.read(r2)
    case Fail{e}:
      IO.pure(Maybe<&2, String>, None{})






# None when the file is missing.
def read_file(+path: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    read_g.open(r)






def write.close(+path: String, r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match r:
    case (f, Done{u}):
      File.close(f)
    case (f, Fail{e}):
      die("cannot write " ++ path)






def write.open(+path: String, +data: String, r: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match r:
    case Done{f}:
      do IO<Unit>:
        r2 : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, data)
        write.close(path, r2)
    case Fail{e}:
      die("cannot open " ++ path ++ " for writing")






def write_file(+path: String, +data: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    write.open(path, data, r)






def git(args: List<String>) -> List<String>:
  "git" <> "-C" <> repo() <> "-c" <> "commit.gpgsign=false" <> args






def sh.status(+ok: Bool, +prog: String, +err: String) -> IO(Unit):
  match ok:
    case True{}:
      done()
    case False{}:
      die("setup command failed: " ++ prog ++ ": " ++ err)






# --- processes ---------------------------------------------------------------------------

def sh.check(+prog: String, r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(Unit):
  match r:
    case Done{(status, (out, err))}:
      sh.status(U32.is_eq(status, 0), prog, err)
    case Fail{(code, msg)}:
      die("cannot run " ++ prog ++ ": " ++ msg)






def sh.run(+prog: String, args: List<String>) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(prog, args, "", max_bytes(), 60000)
    sh.check(prog, r)






# Run a setup command (program first); a non-zero status is fatal.
def sh(cmd: List<String>) -> IO(Unit):
  match cmd:
    case Con{prog, args}:
      sh.run(prog, args)
    case Nil{}:
      die("empty command")






def seq(cmds: List<List<String>>) -> IO(Unit):
  match cmds:
    case Nil{}:
      done()
    case Con{c, rest}:
      IO.bind(Unit, Unit, sh(c), u => seq(rest))






def setup() -> IO(Unit):
  seq([
    ["rm", "-rf", repo()],
    ["mkdir", "-p", repo() ++ "/sub"],
    ["cp", "tests/fixtures/base.bend", repo() ++ "/LAWS.bend"],
    ["cp", "tests/fixtures/base.bend", repo() ++ "/sub/LAWS.bend"],
    git(["init", "-q", "-b", "main"]),
    git(["config", "user.email", "t@example.com"]),
    git(["config", "user.name", "t"]),
    git(["add", "-A"]),
    git(["commit", "-q", "-m", "base"]),
    git(["tag", "v1"]),
    ["cp", "tests/fixtures/removed.bend", repo() ++ "/LAWS.bend"],
    ["cp", "tests/fixtures/added.bend", repo() ++ "/sub/LAWS.bend"],
    git(["commit", "-q", "-am", "next"])
  ])






def teardown() -> IO(Unit):
  sh(["rm", "-rf", repo()])






# --- running one case ------------------------------------------------------------------------

def sed.out(+text: String, r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Done{(status, (out, err))}:
      out
    case Fail{e}:
      text






# Mask the absolute repo root, so goldens do not depend on the checkout path.
def masked(+text: String, +root: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("sed", ["s#" ++ root ++ "#<root>#g"], text, max_bytes(), 60000)
    return sed.out(text, r)






def jq.ok(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Bool:
  match r:
    case Done{(status, (out, err))}:
      U32.is_eq(status, 0)
    case Fail{e}:
      False{}






def json_if(+is_obj: Bool, +out: String) -> IO(Bool):
  match is_obj:
    case True{}:
      do IO<Bool>:
        r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("jq", ["-e", "."], out, max_bytes(), 60000)
        return jq.ok(r)
    case False{}:
      IO.pure(Bool, True{})






# Stdout that looks like JSON must parse.
def json_ok(+out: String) -> IO(Bool):
  json_if(String.starts_with(out, "{"), out)






def golden_eq(+g: Maybe<&2, String>, +actual: String) -> Bool:
  match g:
    case Some{t}:
      String.eq(t, actual)
    case None{}:
      False{}






def flag(+ok: Bool, +msg: String) -> String:
  match ok:
    case True{}:
      ""
    case False{}:
      "  " ++ msg ++ "\n"






def report.if(+ok: Bool, +name: String, +why: String, +out: String) -> IO(U32):
  match ok:
    case True{}:
      do IO<U32>:
        IO.print("ok   " ++ name)
        return 0
    case False{}:
      do IO<U32>:
        IO.print("FAIL " ++ name ++ "\n" ++ why ++ "  stdout was: " ++ String.take(out, 300n))
        return 1






def verdict(+name: String, +want: U32, +status: U32, +out: String, +err: String, +go: Maybe<&2, String>, +ge: Maybe<&2, String>, +jv: Bool) -> IO(U32):
  report.if(
    Bool.and(Bool.and(U32.is_eq(want, status), golden_eq(go, out)), Bool.and(golden_eq(ge, err), jv)),
    name,
    flag(U32.is_eq(want, status), "exit: want " ++ U32.show(want) ++ " got " ++ U32.show(status))
      ++ flag(golden_eq(go, out), "stdout differs from golden/" ++ name ++ ".out")
      ++ flag(golden_eq(ge, err), "stderr differs from golden/" ++ name ++ ".err")
      ++ flag(jv, "stdout is not valid JSON"),
    out)






def refresh(+update: Bool, +name: String, +out: String, +err: String) -> IO(Unit):
  match update:
    case True{}:
      do IO<Unit>:
        write_file("tests/golden/" ++ name ++ ".out", out)
        write_file("tests/golden/" ++ name ++ ".err", err)
    case False{}:
      done()






def compare(+update: Bool, +name: String, +want: U32, +status: U32, +out: String, +err: String) -> IO(U32):
  do IO<U32>:
    refresh(update, name, out, err)
    go : Maybe<&2, String> <- read_file("tests/golden/" ++ name ++ ".out")
    ge : Maybe<&2, String> <- read_file("tests/golden/" ++ name ++ ".err")
    jv : Bool <- json_ok(out)
    verdict(name, want, status, out, err, go, ge, jv)






def after_exec(+update: Bool, +name: String, +want: U32, +root: String, r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(U32):
  match r:
    case Done{(status, (out, err))}:
      do IO<U32>:
        mo : String <- masked(out, root)
        me : String <- masked(err, root)
        compare(update, name, want, status, mo, me)
    case Fail{(code, msg)}:
      IO.die(U32, 2, "cannot run binary for " ++ name ++ ": " ++ msg)






def exec(+bin: String, +update: Bool, +name: String, +want: U32, +root: String, args: List<String>) -> IO(U32):
  do IO<U32>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(bin, args, "", max_bytes(), 60000)
    after_exec(update, name, want, root, r)






def abs_pick(+is_abs: Bool, +a: String, +root: String) -> String:
  match is_abs:
    case True{}:
      root ++ String.drop(a, 5n)
    case False{}:
      a






def abs_args(+args: List<&2, String>, +root: String) -> List<String>:
  match args:
    case Nil{}:
      Nil{}
    case Con{a, rest}:
      abs_pick(String.starts_with(a, "@ABS@"), a, root) <> abs_args(rest, root)






def run_want(+bin: String, +update: Bool, +name: String, +root: String, +args: List<&2, String>, +m: Maybe<&2, U32>) -> IO(U32):
  match m:
    case Some{want}:
      exec(bin, update, name, want, root, abs_args(args, root))
    case None{}:
      IO.die(U32, 2, "tests/cases.txt: bad exit code for " ++ name)






# `absent name path`: the file must not exist (a hostile ref must write nothing).
def absent.check(+name: String, +path: String, r: Maybe<&2, String>) -> IO(U32):
  match r:
    case None{}:
      do IO<U32>:
        IO.print("ok   " ++ name)
        return 0
    case Some{t}:
      do IO<U32>:
        IO.print("FAIL " ++ name ++ ": " ++ path ++ " exists")
        return 1






def run_absent(+name: String, +path: String) -> IO(U32):
  do IO<U32>:
    r : Maybe<&2, String> <- read_file(path)
    absent.check(name, path, r)






def run_parts(+is_absent: Bool, +bin: String, +update: Bool, +root: String, +parts: List<&2, String>) -> IO(U32):
  match is_absent:
    case True{}:
      match parts:
        case Con{k, Con{name, Con{path, Nil{}}}}:
          run_absent(name, path)
        case _:
          IO.die(U32, 2, "tests/cases.txt: bad absent line")
    case False{}:
      match parts:
        case Con{name, Con{rc, args}}:
          run_want(bin, update, name, root, args, U32.read(rc))
        case _:
          IO.die(U32, 2, "tests/cases.txt: bad case line")






def first_is_absent(+parts: List<&2, String>) -> Bool:
  match parts:
    case Con{k, rest}:
      String.eq(k, "absent")
    case Nil{}:
      False{}






def run_line(+bin: String, +update: Bool, +root: String, +line: String) -> IO(U32):
  run_parts(first_is_absent(String.split(line, ' ')), bin, update, root, String.split(line, ' '))






def run_cases(+bin: String, +update: Bool, +root: String, +lines: List<&2, String>) -> IO(U32):
  match lines:
    case Nil{}:
      IO.pure(U32, 0)
    case Con{l, rest}:
      do IO<U32>:
        a : U32 <- run_line(bin, update, root, l)
        b : U32 <- run_cases(bin, update, root, rest)
        return (a + b : U32)






def keep.if(+blank: Bool, +l: String, +rest: List<&2, String>) -> List<&2, String>:
  match blank:
    case True{}:
      rest
    case False{}:
      l <> rest






def keep(+l: String, +rest: List<&2, String>) -> List<&2, String>:
  keep.if(T.blank(l), l, rest)






# --- main ---------------------------------------------------------------------------------------

# Non-blank, non-comment lines, cleaned.
def case_lines(+raw: List<&2, String>) -> List<&2, String>:
  match raw:
    case Nil{}:
      Nil{}
    case Con{l, rest}:
      keep(T.clean(l), case_lines(rest))






def exit_if(+ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      done()
    case False{}:
      IO.exit(1)






def exit_for(+failed: U32) -> IO(Unit):
  exit_if(U32.is_eq(failed, 0))






def summary(+total: U32, +failed: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(U32.sub(total, failed)) ++ " passed; " ++ U32.show(failed) ++ " failed")
    exit_for(failed)






def run_all(+bin: String, +update: Bool, +root: String, +lines: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    setup()
    failed : U32 <- run_cases(bin, update, root, lines)
    teardown()
    summary(U32.from_nat(List.length(&2, String, lines)), failed)






def with_cases(+bin: String, +update: Bool, +root: String, +m: Maybe<&2, String>) -> IO(Unit):
  match m:
    case Some{text}:
      run_all(bin, update, root, case_lines(String.lines(text)))
    case None{}:
      die("cannot read tests/cases.txt (run from the repository root)")






def start(+bin: String, +update: Bool, +root: String) -> IO(Unit):
  do IO<Unit>:
    m : Maybe<&2, String> <- read_file("tests/cases.txt")
    with_cases(bin, update, root, m)






def pwd.out(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Done{(status, (out, err))}:
      String.trim(out)
    case Fail{e}:
      ""






def with_root(+bin: String, +update: Bool) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("pwd", [], "", 4096, 10000)
    start(bin, update, pwd.out(r))






def args2(+bin: String, +flag: String) -> IO(Unit):
  with_root(bin, String.eq(flag, "--update"))






def dispatch(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{bin, Nil{}}}:
      with_root(bin, False{})
    case Con{prog, Con{bin, Con{flag, Nil{}}}}:
      args2(bin, flag)
    case _:
      die("usage: run-tests <path to bend-laws> [--update]")






def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    dispatch(args)
