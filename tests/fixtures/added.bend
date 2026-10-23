# A small LAWS.bend used as the baseline for the diff fixtures.
import Base

# LAW: for every x, x plus 0 equals x
law add_zero:
  for x: Nat
  {Nat.add(x, 0n) == x : Nat}

# LAW: a premise-guarded law, with a multi-line binder
law pred_succ:
  for n: Nat
  for h: {Nat.is_eq(n,
    0n) == False{} : Bool}
  {Nat.add(n, 0n) == n : Nat}

# LAW: a string literal that holds a hash and spaces: only tokens outside
# strings are normalised
law greeting:
  for name: String
  {String.append("hi # there  ", name) == String.append("hi # there  ", name) : String}

# LAW: a statement that continues after a trailing arrow
law arrow:
  for f: Nat
  Nat ->
    Nat

# LAW: new
law mul_one:
  for x: Nat
  {Nat.mul(x, 1n) == x : Nat}
