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
| returnStatement
| invariableStatement
| judgeWithElseStatement
| judgeStatement
| loopStatement
| loopInfiniteStatement
| printStatement
| assignStatement
| expressionStatement
;		  

printStatement:'print' '(' Text ')' Terminate;

// 导出命名空间
exportStatement:Export nameSpace BlockLeft (statement)* BlockRight Terminate;
// 导入命名空间
importStatement:Import BlockLeft (nameSpaceStatement)* BlockRight Terminate;
// 定义包
packageStatement:ID Define Package BlockLeft (statement)* BlockRight Terminate;
// 主函数
functionMainStatement:Main Define Function BlockLeft (statement)* BlockRight Terminate;
// 函数
functionStatement:ID Define Function parameterClauseIn Wave parameterClauseOut BlockLeft (statement)* BlockRight Terminate;
// 返回
returnStatement: ArrowRight expressionList Terminate;
// 入参
parameterClauseIn : '(' parameter? (',' parameter)*  ')'  ;
// 出参
parameterClauseOut : '(' parameter? (',' parameter)*  ')'  ;
// 参数结构
parameter : ID ':' basicType;

// 有else的判断
judgeWithElseStatement:judgeBaseStatement JudgeSub BlockLeft (statement)* BlockRight Terminate;
// 判断
judgeStatement:judgeBaseStatement Terminate;
// 判断基础
judgeBaseStatement:Judge expression BlockLeft (statement)* BlockRight;
// 循环
loopStatement:Loop iteratorStatement Wave ID BlockLeft (statement)* BlockRight Terminate;
// 无限循环
loopInfiniteStatement:Loop BlockLeft (statement)* BlockRight Terminate;
// 迭代器
iteratorStatement:Number '..' Number '..' Number | Number '..' Number;
// 命名空间
nameSpaceStatement:nameSpace Terminate;

// 定义不变量
invariableStatement:expression Define expression Terminate;
// 赋值
assignStatement: expression '=' expression Terminate;

expressionStatement: expression Terminate;

// 基础表达式
primaryExpression: 
t=(ID|Self)
| dataStatement
| '(' expression ')'
;

// 表达式
expression:
primaryExpression
| ID tuple // 函数调用
| expressionList // 表达式列表
| expression call expression // 链式调用
| expression judge expression // 判断型表达式
| expression add expression // 和型表达式
| expression mul expression // 积型表达式
;

expressionList : '(' (expression (',' expression)*)? ')'; // 参数列表

tuple : '(' (ID ':' expression (',' ID ':' expression)* )? ')'; // 元组

nameSpace:ID ('.'ID)* ;

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

judge : op=('||' | '&&' | '==' | '!=' | '<' | '>');
add : op=('+' | '-');
mul : op=('*' | '/');
call : op='.';

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
ID   : [a-zA-Z] [a-zA-Z0-9]*; // 标识符，由多个字母组成

Comment : '/*' .*? '*/' -> skip; // 结构注释
CommentLine : '//' .*? '\r'? '\n' -> skip; // 行注释

//WS : ' ' -> skip;

WS   : [ \t\r\n]+ -> skip; // 空白， 后面的->skip表示antlr4在分析语言的文本时，符合这个规则的词法将被无视