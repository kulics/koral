grammar Coral;

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

printStatement:'print' '(' Text ')' Terminate;

expression : 
	mulDiv ((Add|Sub) mulDiv)* 
;

mulDiv: 
	atom ((Mul|Div) atom)* 
;

atom: '(' expression ')'
	  | Number
	  | ID
;

// 导出命名空间
exportStatement:
Export ID BlockLeft (statement)* BlockRight Terminate
;
// 导入命名空间
importStatement:
Import BlockLeft (nameSpaceStatement)* BlockRight Terminate
;
// 定义包
packageStatement:
ID Define Package BlockLeft (statement)* BlockRight Terminate
;
// 主函数
functionMainStatement:
Main Define Function BlockLeft (statement)* BlockRight Terminate
;
// 函数
functionStatement:
ID Define Function parameterClause Wave basicType BlockLeft (statement)* BlockRight Terminate
;

parameterClause : '(' parameterList ')'  ;
parameterList : basicType? (',' basicType)* ;
// 定义不变量
invariableStatement:
ID Define dataStatement Terminate
;
// 有else的判断
judgeWithElseStatement:
judgeBaseStatement JudgeSub BlockLeft (statement)* BlockRight Terminate
;
// 判断
judgeStatement:
judgeBaseStatement Terminate
;
// 判断基础
judgeBaseStatement:
Judge bool BlockLeft (statement)* BlockRight
;
// 循环
loopStatement:
Loop Number '..' Number BlockLeft (statement)* BlockRight Terminate
;
// 命名空间
nameSpaceStatement:
ID Terminate
;

blockStatement:
BlockLeft (statement)* BlockRight
;

assign: ID '=' expression
;

// 基础数据
dataStatement:
t=Number
| t=Text
| t=True
| t=False
;
// 基础类型名
basicType:
t=TypeNumber
| t=TypeText
| t=TypeBool
;
// bool值
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
fragment DIGIT : [0-9] ;             // 单个数字
Text: '"' (~[\\\r\n])*? '"'; //文本
ID   : [a-zA-Z]+; // 标识符，由多个字母组成

Mul  : '*';
Div  : '/';
Add  : '+';
Sub  : '-';

Comment : '/*' .*? '*/' -> skip; // 结构注释
CommentLine : '//' .*? '\r'? '\n' -> skip; // 行注释

//WS : ' ' -> skip;

WS   : [ \t\r\n]+ -> skip; // 空白， 后面的->skip表示antlr4在分析语言的文本时，符合这个规则的词法将被无视