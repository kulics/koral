# Operator
An operator is a notation that tells a compiler to perform a specific mathematical or logical operation.

We can easily understand the mathematical notation in mathematics, but the programming language has its own differences.

## Arithmetic Operator
Arithmetic operators are mainly used for numerical operations on data types, most of which are in line with the expectations in mathematics.

E.g:
```
a : 4;
b : 2;
c : a + b; // + add
c = a - b; // - subtract
c = a * b; // * multiply
c = a / b; // / divide
c = a % b; // % take the remainder, meaning the remainder after the divisibility, the result here is 2
```
In addition to numbers, there are other types that support arithmetic operations, such as `str`, which can be used to combine two paragraphs of text.

E.g:
```
a : "hello";
b : "world";
c : a + " " + b; // c is "hello world"
```
## Judgment Operator
Judgment operator is mainly used in the judgment statement, used to calculate the relationship between the two data, the result is expected to be true, not expected to be false.

E.g:
```
a : 4;
b : 2;
c : a == b;  // == equal to
c = a ~= b;  // ~= not equal
c = a > b;   // > greater than
c = a >= b;  // >= greater than or equal
c = a < b;   // < less than
c = a <= b;  // <= less than or equal
```
## Logical Operator
Logical operators are also used primarily in judgment statements for logic operations (AND, OR, NOT).

E.g:
```
a : true;
b : false;
c : a && b;  // && and, both true at the same time
c = a || b;  // || or, one of them is true
c = ~~ a;    // ~~ not, boolean negation
```
## Assignment Operator
Assignment operator is mainly used to assign the right data to the left identifier, you can also attach some shortcut.

E.g:
```
a : 0;
a = 1;  // = the simplest assignment
a += 1; // += add first and then assign
a -= 1; // -= subtract first and then assign
a *= 1; // *= multiply first and then assign
a /= 1; // /= divide first and then assign
a %= 1; // %= take remainder first and than assignment
```
## Braces
Sometimes we need to do a mix of multiple data operations within a single statement, which involves priority issues.

At this time we can use `()` to distinguish between priorities, the parentheses will be given priority to the implementation of the operation.

Proposal to use more brackets to express our operation, which is very helpful for the reading of the code.

E.g:
```
a : 1+9%5*5-8/9==5;
b : (1 + (9 % 5 * 5) - (8 / 9)) == 5; 
```
Obviously……

### [Next Chapter](collection-type.md)