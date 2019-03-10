# Operator
An operator is a notation that tells a compiler to perform a specific mathematical or logical operation.

We can easily understand the mathematical notation in mathematics, but the programming language has its own differences.

## Arithmetic Operator
Arithmetic operators are mainly used for numerical operations on data types, most of which are in line with the expectations in mathematics.

E.g:
```
a := 4
b := 2
prt( a + b )    # + add
prt( a - b )    # - subtract
prt( a * b )    # * multiply
prt( a / b )    # / divide
prt( a % b )    # % take the remainder, meaning the remainder after the divisibility, the result here is 2
prt( a ** b )   # ** power
prt( a // b )   # // root
prt( a %% b )   # %% logarithm
```
In addition to numbers, there are other types that support arithmetic operations, such as `str`, which can be used to combine two paragraphs of text.

E.g:
```
a := "hello"
b := "world"
c := a + " " + b    # c is "hello world"
```
## Judgment Operator
Judgment operator is mainly used in the judgment statement, used to calculate the relationship between the two data, the result is expected to be true, not expected to be false.

E.g:
```
a := 4
b := 2
prt( a == b )   # == equal to
prt( a ~= b )   # ~= not equal
prt( a > b )    # > greater than
prt( a >= b )   # >= greater than or equal
prt( a < b )    # < less than
prt( a <= b )   # <= less than or equal
```
## Logical Operator
Logical operators are also used primarily in judgment statements for logic operations (AND, OR, NOT).

E.g:
```
a := true
b := false
prt( a & b )    # & and, both true at the same time
prt( a | b )    # | or, one of them is true
prt( ~a )       # ~ not, boolean negation
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
a := 1
a.and(1)   # bitwise AND
a.or(1)    # bitwise OR
a.xor(1)   # bitwise XOR
a.not()    # bitwise Invert
a.lft(1)   # left shift 
a.rht(1)   # right shift
```
## Braces
Sometimes we need to do a mix of multiple data operations within a single statement, which involves priority issues.

At this time we can use `()` to distinguish between priorities, the parentheses will be given priority to the implementation of the operation.

Proposal to use more brackets to express our operation, which is very helpful for the reading of the code.

E.g:
```
a := 1+9%5*5-8/9==5
b := (1 + (9 % 5 * 5) - (8 / 9)) == 5
```
Obviously……

### [Next Chapter](collection-type.md)