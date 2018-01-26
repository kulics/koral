// Define a grammar called Hello
grammar Grammar;

program : statement+;

//stats : (statement ';')* ; // match zero or more ';'-terminatedstatements

//exprList : expr (',' expr)* ;

statement :
 exportStatement
| importStatement
| packageStatement
| functionMainStatement
| functionStatement
| invariableStatement
| judgeWithElseStatement
| judgeStatement
| loopStatement
| printStatement
;

//defineStatement:
//ID Define Number Terminate # defineInvariable
//| ID Define Package blockStatement Terminate # definePackage
//;
		  

printStatement:'print' '(' Text ')' Terminate;

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

functionMainStatement:
Main Define Function BlockLeft (statement)* BlockRight Terminate
;

functionStatement:
ID Define Function parameterClause Wave basicType BlockLeft (statement)* BlockRight Terminate
;

parameterClause : '(' parameterList ')'  ;
parameterList : basicType? (',' basicType)* ;

invariableStatement:
ID Define dataStatement Terminate
;

judgeWithElseStatement:
judgeBaseStatement JudgeSub BlockLeft (statement)* BlockRight Terminate
;

judgeStatement:
judgeBaseStatement Terminate
;

judgeBaseStatement:
Judge bool BlockLeft (statement)* BlockRight
;

loopStatement:
Loop Number '..' Number BlockLeft (statement)* BlockRight Terminate
;

nameSpaceStatement:
ID Terminate
;

blockStatement:
BlockLeft (statement)* BlockRight
;

dataStatement:
t=Number
| t=Text
| t=True
| t=False
;

basicType:
t=TypeNumber
| t=TypeText
| t=TypeBool
;

bool:t=True|t=False;

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

TypeNumber: 'number';
TypeText: 'text';
TypeBool: 'bool';
True: 'true';
False: 'false';

Main: 'Main';


Number :DIGIT+ ('.' DIGIT+)?; // 数字
fragment DIGIT : [0-9] ;             // match single digit
Text: '"' (~[\\\r\n])*? '"'; //文本
ID   : [a-zA-Z]+; // 标识符，由多个字母组成

Mul  : '*';
Div  : '/';
Add  : '+';
Sub  : '-';

Comment : '/*' .*? '*/' -> skip;
CommentLine : '//' .*? '\r'? '\n' -> skip;

//WS : ' ' -> skip;

WS   : [ \t\r\n]+ -> skip; // 空白， 后面的->skip表示antlr4在分析语言的文本时，符合这个规则的词法将被无视
