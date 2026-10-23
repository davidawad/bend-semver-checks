import Base
import ./text.bend as T
import ./law.bend as L

# Compare the laws of an old and a new LAWS.bend by name.
#
#   removed    a law of the old file with no law of that name in the new one
#   changed    same name, different binders or statement (compared token-wise,
#              see law.bend); `kind` says which way, as far as binders tell
#   added      a law of the new file with no law of that name in the old one
#
# Breaking = anything removed or changed. Additions are not.

type Change is Data:
  Change{kind: String, old: L.Law, new: L.Law}

def list_eq.pair(+same: Bool, +rest: Bool) -> Bool:
  Bool.and(same, rest)

def list_eq(+a: List<&2, String>, +b: List<&2, String>) -> Bool:
  match a:
    case Nil{}:
      List.is_empty(&2, String, b)
    case Con{x, xs}:
      match b:
        case Nil{}:
          False{}
        case Con{y, ys}:
          list_eq.pair(String.eq(x, y), list_eq(xs, ys))

def subseq.pick(+hit: Bool, +skip: Bool, +take: Bool) -> Bool:
  match hit:
    case True{}:
      Bool.or(take, skip)
    case False{}:
      skip

# Is xs a subsequence of ys?
def subseq(+xs: List<&2, String>, +ys: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{x, xt}:
      match ys:
        case Nil{}:
          False{}
        case Con{y, yt}:
          subseq.pick(String.eq(x, y), subseq(xs, yt), subseq(xt, yt))

# Same statement, different binders: premises added weaken the law, premises
# dropped strengthen it. Anything else is just `changed`.
def kind.binders(+grew: Bool, +shrank: Bool) -> String:
  match grew:
    case True{}:
      "weakened"
    case False{}:
      match shrank:
        case True{}:
          "strengthened"
        case False{}:
          "changed"

def kind.if(+same_stmt: Bool, +ob: List<&2, String>, +nb: List<&2, String>) -> String:
  match same_stmt:
    case True{}:
      kind.binders(subseq(ob, nb), subseq(nb, ob))
    case False{}:
      "changed"

def kind(+o: L.Law, +n: L.Law) -> String:
  match o:
    case L.Law{on, ol, ob, os}:
      match n:
        case L.Law{nn, nl, nb, ns}:
          kind.if(String.eq(os, ns), ob, nb)

def same_law(+o: L.Law, +n: L.Law) -> Bool:
  match o:
    case L.Law{on, ol, ob, os}:
      match n:
        case L.Law{nn, nl, nb, ns}:
          list_eq.pair(String.eq(os, ns), list_eq(ob, nb))

# --- the three lists -----------------------------------------------------------

def removed.pick(+m: Maybe<&2, L.Law>, +o: L.Law, +rest: List<&2, L.Law>) -> List<&2, L.Law>:
  match m:
    case None{}:
      o <> rest
    case Some{x}:
      rest

# Laws of `a` whose name is absent from `b`, in order.
def only_in(+a: List<&2, L.Law>, +b: List<&2, L.Law>) -> List<&2, L.Law>:
  match a:
    case Nil{}:
      Nil{}
    case Con{l, rest}:
      match l:
        case L.Law{+n, line, bs, st}:
          removed.pick(L.find(n, b), L.Law{n, line, bs, st}, only_in(rest, b))

def changed.judge(+same: Bool, +k: String, +o: L.Law, +n: L.Law, +rest: List<&2, Change>) -> List<&2, Change>:
  match same:
    case True{}:
      rest
    case False{}:
      Change{k, o, n} <> rest

def changed.pick(+m: Maybe<&2, L.Law>, +o: L.Law, +rest: List<&2, Change>) -> List<&2, Change>:
  match m:
    case None{}:
      rest
    case Some{n}:
      changed.judge(same_law(o, n), kind(o, n), o, n, rest)

# Same-name pairs that differ, in old-file order.
def changed(+a: List<&2, L.Law>, +b: List<&2, L.Law>) -> List<&2, Change>:
  match a:
    case Nil{}:
      Nil{}
    case Con{l, rest}:
      match l:
        case L.Law{+n, line, bs, st}:
          changed.pick(L.find(n, b), L.Law{n, line, bs, st}, changed(rest, b))

# --- verdict and report -------------------------------------------------------------

def breaking(+old: List<&2, L.Law>, +new: List<&2, L.Law>) -> Bool:
  Bool.or(
    Bool.not(List.is_empty(&2, L.Law, only_in(old, new))),
    Bool.not(List.is_empty(&2, Change, changed(old, new))))

def count(+xs: List<&2, L.Law>) -> String:
  U32.show(U32.from_nat(List.length(&2, L.Law, xs)))

def count_c(+xs: List<&2, Change>) -> String:
  U32.show(U32.from_nat(List.length(&2, Change, xs)))

def bool_json(+b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def change_json(+c: Change) -> String:
  match c:
    case Change{k, o, n}:
      match o:
        case L.Law{+name, ol, ob, os}:
          "{\"name\":" ++ T.jstr(name) ++ ",\"kind\":" ++ T.jstr(k) ++ ",\"old\":" ++ L.law_json(L.Law{name, ol, ob, os}) ++ ",\"new\":" ++ L.law_json(n) ++ "}"

def changes_json.go(+cs: List<&2, Change>) -> String:
  match cs:
    case Nil{}:
      ""
    case Con{c, rest}:
      "," ++ change_json(c) ++ changes_json.go(rest)

def changes_json(+cs: List<&2, Change>) -> String:
  match cs:
    case Nil{}:
      "[]"
    case Con{c, rest}:
      "[" ++ change_json(c) ++ changes_json.go(rest) ++ "]"

def report.of(+oldp: String, +newp: String, +nold: U32, +rem: List<&2, L.Law>, +chg: List<&2, Change>, +add: List<&2, L.Law>) -> String:
  "{\"old\":" ++ T.jstr(oldp) ++ ",\"new\":" ++ T.jstr(newp)
  ++ ",\"breaking\":" ++ bool_json(Bool.not(Bool.and(List.is_empty(&2, L.Law, rem), List.is_empty(&2, Change, chg))))
  ++ ",\"summary\":{\"removed\":" ++ count(rem)
  ++ ",\"changed\":" ++ count_c(chg)
  ++ ",\"added\":" ++ count(add)
  ++ ",\"unchanged\":" ++ U32.show(U32.sub(nold, U32.add(U32.from_nat(List.length(&2, L.Law, rem)), U32.from_nat(List.length(&2, Change, chg)))))
  ++ "},\"removed\":" ++ L.laws_json(rem)
  ++ ",\"changed\":" ++ changes_json(chg)
  ++ ",\"added\":" ++ L.laws_json(add) ++ "}"

# The JSON report for old -> new. oldp/newp label the two sides.
def report(+oldp: String, +newp: String, +old: List<&2, L.Law>, +new: List<&2, L.Law>) -> String:
  report.of(oldp, newp, U32.from_nat(List.length(&2, L.Law, old)), only_in(old, new), changed(old, new), only_in(new, old))
