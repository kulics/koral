// Define a grammar called Hello
grammar Grammar;

program : statement+;

//stats : (statement ';')* ; // match zero or more ';'-terminatedstatements

//exprList : expr (',' expr)* ;

statement :
 exportStatement
| importStatement
| packageStatement
| functionStatement
| invariableStatement
;

//defineStatement:
//ID Define Number Terminate # defineInvariable
//| ID Define Package blockStatement Terminate # definePackage
//;
		  

//print:
//'print' '[' expr ']' ';';

//expression : 
//	mulDiv ((Add|Sub) mulDiv)* 
//;

//mulDiv: 
//	atom ((Mul|Div) atom)* 
//;

//atom: '(' expression ')'
//	  | INT
//	  | ID
//;


exportStatement:
Export ID BlockLeft (statement)* BlockRight Terminate
;

importStatement:
Import BlockLeft (nameSpaceStatement)* BlockRight Terminate
;

packageStatement:
ID Define Package BlockLeft (statement)* BlockRight Terminate
;

functionStatement:
ID Define Function basicType Wave basicType BlockLeft (statement)* BlockRight Terminate
;

invariableStatement:
ID Define Number Terminate
;

nameSpaceStatement:
ID Terminate Package
;

blockStatement:
BlockLeft (statement)* BlockRight
;

basicType:
num='number'
| txt='text'
| bl='bool'
;

Terminate : ';';

BlockLeft : '{';
BlockRight : '}';

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

ID   : [a-zA-Z]+; // 标识符，由多个字母组成
//INT : '0'..'9' + ;  // 整数
Number  : [0-9]+('.'([0-9]+)?)?
        | [0-9]+; // 数字
NEWLINE:'\r' ? '\n' ; 

Mul  : '*';
Div  : '/';
Add  : '+';
Sub  : '-';

Comment : '/*' .*? '*/' -> skip;
CommentLine : '//' .*? '\r'? '\n' -> skip;

//WS : ' ' -> skip;

WS   : [ \t\r\n]+ -> skip; // 空白， 后面的->skip表示antlr4在分析语言的文本时，符合这个规则的词法将被无视
