// Define a grammar called Hello
grammar xylang;

prog : stat+;

stats : (stat ';')* ; // match zero or more ';'-terminatedstatements

exprList : expr (',' expr)* ;

stat : expr             # printExpr
     | ID '=' expr      # assign
     | 'print(' ID ')'  # print
     ;

expr : <assoc=right> expr '^' expr # power
     | expr op=(Mul|Div) expr   # MulDiv
     | expr op=(Add|Sub) expr   # AddSub
     | sign=(Add|Sub)?Number       # number
     | ID                       # id
     | '(' expr ')'             # parens
     ;

Terminate : ';';

Define : '=>';
Redefine: '<=';

Import : '<:';
Export : ':>';

Self : '^';

ArrowRight : '->';
ArrowLeft : '<-';

JudgeSub : '~?';
Judge : '?';

LoopSub : '~@';
Loop : '@';

ExcptionSub : '~!';
Excption : '!';

FunctionSub : '~$';
Function : '$';

PackageSub : '~#';
Package : '#';

ProtocolSub : '~|';
Protocol : '|';

Wave : '~';

ID   : [a-zA-Z]+;
Number  : [0-9]+('.'([0-9]+)?)?
        | [0-9]+;

Mul  : '*';
Div  : '/';
Add  : '+';
Sub  : '-';

Comment : '/*' .*? '*/' -> skip;
CommentLine : '//' .*? '\r'? '\n' -> skip;

WS   : [ \t\r\n]+ -> skip;