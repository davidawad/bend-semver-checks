import Base

law add_zero:
  for x: Nat
  for h: {x == 0n : Nat}
  {Nat.add(x, 0n) == x : Nat}

law mul_one:
  for x: Nat
  {Nat.mul(x, 1n) == x : Nat}

law mul_zero:
  for x: Nat
  {Nat.mul(x, 0n) == 0n : Nat}
