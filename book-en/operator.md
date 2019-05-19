# Operator
An operator is A notation that tells A compiler to perform A specific mathematical or logical operation.

We can easily understand the mathematical notation in mathematics, but the programming language has its own differences.

## Arithmetic Operator
Arithmetic operators are mainly used for numerical operations on data types, most of which are in line with the expectations in mathematics.

E.g:
```
A := 4
B := 2
Prt( A + B )    # + add
Prt( A - B )    # - subtract
Prt( A * B )    # * multiply
Prt( A / B )    # / divide
Prt( A % B )    # % take the remainder, meaning the remainder after the divisibility, the result here is 2
Prt( A ** B )   # ** power
Prt( A // B )   # // root
Prt( A %% B )   # %% logarithm
```
In addition to numbers, there are other types that support arithmetic operations, such as `Str`, which can be used to combine two paragraphs of text.

E.g:
```
A := "hello"
B := "world"
C := A + " " + B    # C is "hello world"
```
## Judgment Operator
Judgment operator is mainly used in the judgment statement, used to calculate the relationship between the two data, the result is expected to be true, not expected to be false.

E.g:
```
A := 4
B := 2
Prt( A == B )   # == equal to
Prt( A >< B )   # >< not equal
Prt( A > B )    # > greater than
Prt( A >= B )   # >= greater than or equal
Prt( A < B )    # < less than
Prt( A <= B )   # <= less than or equal
```
## Logical Operator
Logical operators are also used primarily in judgment statements for logic operations (AND, OR, NOT).

E.g:
```
A := True
B := False
Prt( A & B )    # & and, both true at the same time
Prt( A | B )    # | or, one of them is true
Prt( ~A )       # ~ not, boolean negation
```
## Assignment Operator
Assignment operator is mainly used to assign the right data to the left identifier, you can also attach some shortcut.

E.g:
```
A := 0
A = 1   # = the simplest assignment
A += 1  # += add first and then assign
A -= 1  # -= subtract first and then assign
A *= 1  # *= multiply first and then assign
A /= 1  # /= divide first and then assign
A %= 1  # %= take remainder first and than assignment
```
## Bit Operation
In this language, no special symbols are set for bit operations, and function operations are used to perform bit operations.

E.g:
```
A := 1
A.and(1)   # bitwise AND
A.or(1)    # bitwise OR
A.xor(1)   # bitwise XOR
A.not()    # bitwise Invert
A.lft(1)   # left shift 
A.rht(1)   # right shift
```
## Braces
Sometimes we need to do A mix of multiple data operations within A single statement, which involves priority issues.

At this time we can use `()` to distinguish between priorities, the parentheses will be given priority to the implementation of the operation.

Proposal to use more brackets to express our operation, which is very helpful for the reading of the code.

E.g:
```
A := 1+9%5*5-8/9==5
B := (1 + (9 % 5 * 5) - (8 / 9)) == 5
```
Obviously……

### [Next Chapter](collection-type.md)