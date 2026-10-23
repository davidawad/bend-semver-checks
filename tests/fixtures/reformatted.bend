import Base
law add_zero:    # no semantic change
    for   x:   Nat
    {Nat.add(x,    0n)   ==   x : Nat}

law pred_succ:
  for n: Nat
  for h: {Nat.is_eq(n, 0n) == False{} : Bool}
  {Nat.add(n, 0n) == n : Nat}
law greeting:
  for name: String
  {String.append("hi # there  ", name) == String.append("hi # there  ", name) : String}
law arrow:
  for f: Nat
  Nat -> Nat
