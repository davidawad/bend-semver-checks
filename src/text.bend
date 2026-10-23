import Base

# Text helpers: string-aware cleanup of a source line, bracket depth, JSON.
#
# Bend forbids mutual recursion, so the scanners are one recursive loop each
# (`clean.go`, `depth.go`) over a small lexical-mode state machine; the
# transition functions are non-recursive.

# --- lexical modes ----------------------------------------------------------

# Where the scanner is inside a source line.
#   MCode      ordinary code
#   MStr       inside "..."            MStrEsc    after a backslash in one
#   MQuote     right after an opening ' (char literal); the next char is copied
#   MQuoteEsc  after `'\`              MQuoteEnd  expecting the closing '
#   MComment   after `#`, to the end of the line
type Mode is Data:
  MCode{}
  MStr{}
  MStrEsc{}
  MQuote{}
  MQuoteEsc{}
  MQuoteEnd{}
  MComment{}

# The mode after a char read in code.
def advance.code(+c: Char) -> Mode:
  match c:
    case '#':
      MComment{}
    case '"':
      MStr{}
    case '\'':
      MQuote{}
    case _:
      MCode{}

def advance.str(+c: Char) -> Mode:
  match c:
    case '\\':
      MStrEsc{}
    case '"':
      MCode{}
    case _:
      MStr{}

def advance.quote(+c: Char) -> Mode:
  match c:
    case '\\':
      MQuoteEsc{}
    case _:
      MQuoteEnd{}

# A lone prime that is not a char literal falls back to code.
def norm.end(+c: Char) -> Mode:
  match c:
    case '\'':
      MQuoteEnd{}
    case _:
      MCode{}

def norm(+m: Mode, +c: Char) -> Mode:
  match m:
    case MCode{}:
      MCode{}
    case MStr{}:
      MStr{}
    case MStrEsc{}:
      MStrEsc{}
    case MQuote{}:
      MQuote{}
    case MQuoteEsc{}:
      MQuoteEsc{}
    case MQuoteEnd{}:
      norm.end(c)
    case MComment{}:
      MComment{}

# The mode after c; m is already normalised.
def advance(+m: Mode, +c: Char) -> Mode:
  match m:
    case MCode{}:
      advance.code(c)
    case MStr{}:
      advance.str(c)
    case MStrEsc{}:
      MStr{}
    case MQuote{}:
      advance.quote(c)
    case MQuoteEsc{}:
      MQuoteEnd{}
    case MQuoteEnd{}:
      MCode{}
    case MComment{}:
      MComment{}

# --- clean: drop comments, collapse whitespace, trim ------------------------

# Scanner state: the mode, a pending gap (whitespace seen in code, written as
# one space before the next char), and the output so far, reversed.
type St is Data:
  St{mode: Mode, gap: Bool, acc: String}

# A pending gap is written as one space, never at the start of the output.
def put.gap(+acc: String, +c: Char) -> String:
  match acc:
    case SNil{}:
      SCon{c, SNil{}}
    case SCon{h, t}:
      SCon{c, SCon{' ', SCon{h, t}}}

def put(+gap: Bool, +c: Char, +acc: String) -> String:
  match gap:
    case True{}:
      put.gap(acc, c)
    case False{}:
      SCon{c, acc}

# A char read in code (mode MCode): space opens a gap, `#` starts a comment.
def clean.code(+sp: Bool, +c: Char, +gap: Bool, +acc: String) -> St:
  match sp:
    case True{}:
      St{MCode{}, True{}, acc}
    case False{}:
      match c:
        case '#':
          St{MComment{}, gap, acc}
        case _:
          St{advance.code(c), False{}, put(gap, c, acc)}

def clean.step1(+m: Mode, +c: Char, +sp: Bool, +gap: Bool, +acc: String) -> St:
  match m:
    case MCode{}:
      clean.code(sp, c, gap, acc)
    case MStr{}:
      St{advance(MStr{}, c), False{}, SCon{c, acc}}
    case MStrEsc{}:
      St{MStr{}, False{}, SCon{c, acc}}
    case MQuote{}:
      St{advance(MQuote{}, c), False{}, SCon{c, acc}}
    case MQuoteEsc{}:
      St{MQuoteEnd{}, False{}, SCon{c, acc}}
    case MQuoteEnd{}:
      St{MCode{}, False{}, SCon{c, acc}}
    case MComment{}:
      St{MComment{}, gap, acc}

def clean.step(+m: Mode, +c: Char, +gap: Bool, +acc: String) -> St:
  clean.step1(norm(m, c), c, Char.is_space(c), gap, acc)

def clean.go(+s: String, +st: St) -> String:
  match s:
    case SNil{}:
      match st:
        case St{mode, gap, acc}:
          String.reverse(acc)
    case SCon{c, t}:
      match st:
        case St{mode, gap, acc}:
          clean.go(t, clean.step(mode, c, gap, acc))

# Drop a `#` comment (outside strings and char literals), collapse runs of
# whitespace outside strings to one space, trim both ends.
def clean(+s: String) -> String:
  clean.go(s, St{MCode{}, False{}, SNil{}})

# --- bracket depth -----------------------------------------------------------

type DSt is Data:
  DSt{mode: Mode, depth: U32}

def dec.if(+z: Bool, +d: U32) -> U32:
  match z:
    case True{}:
      0
    case False{}:
      U32.sub(d, 1)

def dec(+d: U32) -> U32:
  dec.if(U32.is_eq(d, 0), d)

# Depth change for a char read in code.
def bracket(+c: Char, +d: U32) -> U32:
  match c:
    case '(':
      U32.add(d, 1)
    case '[':
      U32.add(d, 1)
    case '{':
      U32.add(d, 1)
    case ')':
      dec(d)
    case ']':
      dec(d)
    case '}':
      dec(d)
    case _:
      d

def depth.step1(+m: Mode, +c: Char, +d: U32) -> DSt:
  match m:
    case MCode{}:
      DSt{advance.code(c), bracket(c, d)}
    case MStr{}:
      DSt{advance(MStr{}, c), d}
    case MStrEsc{}:
      DSt{MStr{}, d}
    case MQuote{}:
      DSt{advance(MQuote{}, c), d}
    case MQuoteEsc{}:
      DSt{MQuoteEnd{}, d}
    case MQuoteEnd{}:
      DSt{MCode{}, d}
    case MComment{}:
      DSt{MComment{}, d}

def depth.go(+s: String, +st: DSt) -> U32:
  match s:
    case SNil{}:
      match st:
        case DSt{mode, d}:
          d
    case SCon{+c, t}:
      match st:
        case DSt{mode, d}:
          depth.go(t, depth.step1(norm(mode, c), c, d))

# Open-bracket depth after s, starting from depth d (saturating at 0).
def depth_after(+s: String, +d: U32) -> U32:
  depth.go(s, DSt{MCode{}, d})

# --- small string predicates ---------------------------------------------------

def blank(+s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      False{}

def indented(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      match c:
        case ' ':
          True{}
        case '\t':
          True{}
        case _:
          False{}

# --- JSON ---------------------------------------------------------------------------

def hex_digit.if(+lt: Bool, +d: U32) -> Char:
  match lt:
    case True{}:
      Char.from_u32(U32.add(48, d))
    case False{}:
      Char.from_u32(U32.add(87, d))

def hex_digit(+d: U32) -> Char:
  hex_digit.if(U32.is_lt(d, 10), d)

def esc.ctl(+lt: Bool, +x: U32, +c: Char) -> String:
  match lt:
    case True{}:
      "\\u00" ++ SCon{hex_digit(U32.div(x, 16)), SCon{hex_digit(U32.mod(x, 16)), SNil{}}}
    case False{}:
      SCon{c, SNil{}}

def esc.char(+c: Char) -> String:
  match c:
    case '"':
      "\\\""
    case '\\':
      "\\\\"
    case '\n':
      "\\n"
    case '\t':
      "\\t"
    case '\r':
      "\\r"
    case _:
      esc.ctl(U32.is_lt(Char.to_u32(c), 32), Char.to_u32(c), c)

def esc(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{c, t}:
      esc.char(c) ++ esc(t)

# A JSON string literal.
def jstr(+s: String) -> String:
  "\"" ++ esc(s) ++ "\""

def jstrs.go(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      "," ++ jstr(h) ++ jstrs.go(t)

# A JSON array of strings.
def jstrs(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      "[]"
    case Con{h, t}:
      "[" ++ jstr(h) ++ jstrs.go(t) ++ "]"
