import Base
import ./text.bend as T

# Law extraction from a LAWS.bend text.
#
# Surface the extractor relies on (Bend 2.0.38):
#
#   law name:            a header at column 0 (the block ends at the next
#     for x: A             non-blank, non-indented line)
#     exs y: B           binders: lines starting `for ` or `exs `
#     {f(x) == g(x) : A} the statement: everything else in the block
#
# Comments and extra whitespace are ignored (T.clean), so a reformat that does
# not change tokens is not a change. A bracketed or `->`-trailing line continues
# onto the next one, so a binder or statement may span lines.

type Law is Data:
  Law{name: String, line: U32, binders: List<&2, String>, statement: String}

# One physical line: 1-based number, whether it starts with a space or tab,
# and its cleaned text.
type Ln is Data:
  Ln{no: U32, ind: Bool, text: String}

# A law block before its body is split: header name, header line, body lines
# (cleaned, newest first while scanning).
type Block is Data:
  Block{name: String, line: U32, body: List<&2, String>}

type Cur is Data:
  NoCur{}
  InLaw{block: Block}

type PErr is Data:
  NoErr{}
  PErr{line: U32, msg: String}

# Scanner state: the open block, closed blocks (newest first), first error.
type SS is Data:
  SS{cur: Cur, acc: List<&2, Block>, err: PErr}

type Hdr is Data:
  Hdr{name: String, rest: String}
  NoHdr{}

# The outcome of parsing: the laws in file order, or the first error.
type Parsed is Data:
  Good{laws: List<&2, Law>}
  Bad{line: U32, msg: String}

# --- phase 0: lines ----------------------------------------------------------

def lns(+rs: List<&2, String>, +n: U32) -> List<&2, Ln>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Ln{n, T.indented(h), T.clean(h)} <> lns(t, U32.add(n, 1))

# --- phase 1: blocks -------------------------------------------------------------

# `law name: rest` after the `law ` prefix, split at the first colon.
def colon(+s: String, +name: String) -> Hdr:
  match s:
    case SNil{}:
      NoHdr{}
    case SCon{+c, t}:
      match c:
        case ':':
          Hdr{String.reverse(name), t}
        case _:
          colon(t, SCon{c, name})

def valid.if(+ok: Bool, +name: String, +rest: String) -> Hdr:
  match ok:
    case True{}:
      Hdr{name, rest}
    case False{}:
      NoHdr{}

def valid(+h: Hdr) -> Hdr:
  match h:
    case Hdr{name, rest}:
      valid.if(Bool.not(Bool.or(T.blank(name), String.contains(name, " "))), name, rest)
    case NoHdr{}:
      NoHdr{}

def header(+text: String) -> Hdr:
  valid(colon(String.drop(text, 4n), SNil{}))

# The body of a block opened by a header: the text after the colon, if any.
def first_body.if(+b: Bool, +rest: String) -> List<&2, String>:
  match b:
    case True{}:
      Nil{}
    case False{}:
      [String.trim(rest)]

def first_body(+rest: String) -> List<&2, String>:
  first_body.if(T.blank(rest), rest)

def flush(+cur: Cur, +acc: List<&2, Block>) -> List<&2, Block>:
  match cur:
    case NoCur{}:
      acc
    case InLaw{b}:
      b <> acc

def set_err(+err: PErr, +no: U32, +msg: String) -> PErr:
  match err:
    case NoErr{}:
      PErr{no, msg}
    case PErr{l, m}:
      PErr{l, m}

def open.hdr(+no: U32, +text: String, +acc: List<&2, Block>, +err: PErr, +h: Hdr) -> SS:
  match h:
    case Hdr{name, rest}:
      SS{InLaw{Block{name, no, first_body(rest)}}, acc, err}
    case NoHdr{}:
      SS{NoCur{}, acc, set_err(err, no, "malformed law header: expected `law <name>:`")}

# Keep the first error.
def push_body(+text: String, +cur: Cur) -> Cur:
  match cur:
    case NoCur{}:
      NoCur{}
    case InLaw{b}:
      match b:
        case Block{name, line, body}:
          InLaw{Block{name, line, text <> body}}

# A non-blank column-0 line closes the open block; `law ` opens a new one.
def close_line(+is_law: Bool, +no: U32, +text: String, +ss: SS) -> SS:
  match is_law:
    case True{}:
      match ss:
        case SS{cur, acc, err}:
          open.hdr(no, text, flush(cur, acc), err, header(text))
    case False{}:
      match ss:
        case SS{cur, acc, err}:
          SS{NoCur{}, flush(cur, acc), err}

def indented_line(+text: String, +ss: SS) -> SS:
  match ss:
    case SS{cur, acc, err}:
      SS{push_body(text, cur), acc, err}

# Dispatch order matches binder order: blank, ind, is_law, then the state.
def step(+blank: Bool, +ind: Bool, +is_law: Bool, +no: U32, +text: String, +ss: SS) -> SS:
  match blank:
    case True{}:
      ss
    case False{}:
      match ind:
        case True{}:
          indented_line(text, ss)
        case False{}:
          close_line(is_law, no, text, ss)

def scan(+ls: List<&2, Ln>, +ss: SS) -> SS:
  match ls:
    case Nil{}:
      ss
    case Con{l, rest}:
      match l:
        case Ln{no, ind, +text}:
          scan(rest, step(T.blank(text), ind, String.starts_with(text, "law "), no, text, ss))

def blocks(+ls: List<&2, Ln>) -> SS:
  scan(ls, SS{NoCur{}, Nil{}, NoErr{}})

# --- phase 2: a block becomes a law --------------------------------------------------

# Logical entries: a line continues the previous one while a bracket is open
# or the previous one ends in `->`. State: bracket depth, current entry,
# finished entries (newest first).
type ES is Data:
  ES{d: U32, cur: String, acc: List<&2, String>}

def push_entry.if(+b: Bool, +cur: String, +acc: List<&2, String>) -> List<&2, String>:
  match b:
    case True{}:
      acc
    case False{}:
      cur <> acc

def entry_step(+cont: Bool, +l: String, +d: U32, +cur: String, +acc: List<&2, String>) -> ES:
  match cont:
    case True{}:
      ES{T.depth_after(l, d), cur ++ " " ++ l, acc}
    case False{}:
      ES{T.depth_after(l, 0), l, push_entry.if(T.blank(cur), cur, acc)}

def entries(+ls: List<&2, String>, +es: ES) -> List<&2, String>:
  match ls:
    case Nil{}:
      match es:
        case ES{d, cur, acc}:
          List.reverse(&2, String, push_entry.if(T.blank(cur), cur, acc))
    case Con{l, rest}:
      match es:
        case ES{+d, +cur, acc}:
          entries(rest, entry_step(Bool.or(U32.is_gt(d, 0), String.ends_with(cur, "->")), l, d, cur, acc))

# Binders and statement parts, each newest first.
type PS is Data:
  PS{bs: List<&2, String>, ss: List<&2, String>}

def part.put(+isb: Bool, +e: String, +bs: List<&2, String>, +ss: List<&2, String>) -> PS:
  match isb:
    case True{}:
      PS{e <> bs, ss}
    case False{}:
      PS{bs, e <> ss}

def is_binder(+e: String) -> Bool:
  Bool.or(String.starts_with(e, "for "), String.starts_with(e, "exs "))

def part(+es: List<&2, String>, +ps: PS) -> PS:
  match es:
    case Nil{}:
      ps
    case Con{+e, rest}:
      match ps:
        case PS{bs, ss}:
          part(rest, part.put(is_binder(e), e, bs, ss))

def with_statement.if(+empty: Bool, +name: String, +line: U32, +bs: List<&2, String>, +st: String) -> Parsed:
  match empty:
    case True{}:
      Bad{line, "law `" ++ name ++ "` has no statement"}
    case False{}:
      Good{[Law{name, line, bs, st}]}

def with_statement(+name: String, +line: U32, +bs: List<&2, String>, +st: String) -> Parsed:
  with_statement.if(T.blank(st), name, line, bs, st)

def from_parts(+name: String, +line: U32, +ps: PS) -> Parsed:
  match ps:
    case PS{bs, ss}:
      with_statement(name, line, List.reverse(&2, String, bs), String.join(List.reverse(&2, String, ss), " "))

def build(+b: Block) -> Parsed:
  match b:
    case Block{name, line, body}:
      from_parts(name, line, part(entries(List.reverse(&2, String, body), ES{0, "", Nil{}}), PS{Nil{}, Nil{}}))

def join(+p: Parsed, +q: Parsed) -> Parsed:
  match p:
    case Good{ls}:
      match q:
        case Good{ms}:
          Good{List.append(&2, Law, ls, ms)}
        case Bad{l, m}:
          Bad{l, m}
    case Bad{l, m}:
      Bad{l, m}

def build_all(+bs: List<&2, Block>) -> Parsed:
  match bs:
    case Nil{}:
      Good{Nil{}}
    case Con{b, rest}:
      join(build(b), build_all(rest))

# --- phase 3: duplicate names ------------------------------------------------------------

def find.pick(+eq: Bool, +l: Law, +rest: Maybe<&2, Law>) -> Maybe<&2, Law>:
  match eq:
    case True{}:
      Some{l}
    case False{}:
      rest

def find(+name: String, +ls: List<&2, Law>) -> Maybe<&2, Law>:
  match ls:
    case Nil{}:
      None{}
    case Con{l, rest}:
      match l:
        case Law{+n, line, bs, st}:
          find.pick(String.eq(n, name), Law{n, line, bs, st}, find(name, rest))

def dup.pick(+m: Maybe<&2, Law>, +line: U32, +name: String, +next: Parsed) -> Parsed:
  match m:
    case Some{l}:
      match l:
        case Law{n, ln, bs, st}:
          Bad{ln, "duplicate law `" ++ name ++ "` (first at line " ++ U32.show(line) ++ ")"}
    case None{}:
      next

def dups(+ls: List<&2, Law>) -> Parsed:
  match ls:
    case Nil{}:
      Good{Nil{}}
    case Con{l, rest}:
      match l:
        case Law{+n, line, bs, st}:
          dup.pick(find(n, rest), line, n, dups(rest))

def ensure.go(+d: Parsed, +ls: List<&2, Law>) -> Parsed:
  match d:
    case Good{x}:
      Good{ls}
    case Bad{l, m}:
      Bad{l, m}

def ensure(+p: Parsed) -> Parsed:
  match p:
    case Good{ls}:
      ensure.go(dups(ls), ls)
    case Bad{l, m}:
      Bad{l, m}

def finish.err(+err: PErr, +p: Parsed) -> Parsed:
  match err:
    case NoErr{}:
      ensure(p)
    case PErr{l, m}:
      Bad{l, m}

def finish(+ss: SS) -> Parsed:
  match ss:
    case SS{cur, acc, err}:
      finish.err(err, build_all(List.reverse(&2, Block, flush(cur, acc))))

# All laws of a LAWS.bend text, in file order, or the first parse error.
def parse(+text: String) -> Parsed:
  finish(blocks(lns(String.lines(text), 1)))

# --- JSON ---------------------------------------------------------------------

def law_json(+l: Law) -> String:
  match l:
    case Law{name, line, binders, statement}:
      "{\"name\":" ++ T.jstr(name) ++ ",\"line\":" ++ U32.show(line) ++ ",\"binders\":" ++ T.jstrs(binders) ++ ",\"statement\":" ++ T.jstr(statement) ++ "}"

def laws_json.go(+ls: List<&2, Law>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{l, rest}:
      "," ++ law_json(l) ++ laws_json.go(rest)

def laws_json(+ls: List<&2, Law>) -> String:
  match ls:
    case Nil{}:
      "[]"
    case Con{l, rest}:
      "[" ++ law_json(l) ++ laws_json.go(rest) ++ "]"
