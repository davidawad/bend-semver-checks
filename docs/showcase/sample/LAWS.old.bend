import Base

law add_zero:
  for x: Nat
  {Nat.add(x, 0n) == x : Nat}

law add_comm:
  for a: Nat
  for b: Nat
  {Nat.add(a, b) == Nat.add(b, a) : Nat}

law mul_one:
  for x: Nat
  {Nat.mul(x, 1n) == x : Nat}
