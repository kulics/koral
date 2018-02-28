grammar Xy;

program : statement+;

//stats : (statement ';')* ; // match zero or more ';'-terminatedstatements

//exprList : expr (',' expr)* ;

statement :exportStatement;		  

// 导出命名空间
exportStatement:Export nameSpace BlockLeft (exportSupportStatement)* BlockRight Terminate;
// 导出命名空间支持的语句
exportSupportStatement:
importStatement
|packageStatement
|protocolStatement
|functionMainStatement
;
// 导入命名空间
importStatement:Import BlockLeft (nameSpaceStatement)* BlockRight Terminate;
// 主函数
functionMainStatement:Function BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 定义包
packageStatement:(attribute)? id (templateDefine)? Define Package (Wave parameterClauseIn)? BlockLeft (packageSupportStatement)* BlockRight Terminate;
// 包支持的语句
packageSupportStatement:
packageStatement
|packageVariableStatement
|packageInitStatement
|packageExtend
|protocolStatement
|protocolImplementStatement
|packageFunctionStatement
;
// 包构造方法
packageInitStatement:PackageSub BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 定义变量
packageVariableStatement:(attribute)? expression Define expression Terminate;
// 函数
packageFunctionStatement:id (templateDefine)? Define t=(Function|FunctionAsync) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 定义引入
packageExtend: PackageSub nameSpace Terminate;

// 协议
protocolStatement: id (templateDefine)? Define Protocol BlockLeft (protocolSupportStatement)* BlockRight Terminate;
// 协议支持的语句
protocolSupportStatement:
protocolStatement
|protocolVariableStatement
|protocolFunctionStatement
;
// 定义变量
protocolVariableStatement:expression Define expression Terminate;
// 函数
protocolFunctionStatement:id (templateDefine)? Define t=(Function|FunctionAsync) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 协议实现支持的语句
protocolImplementSupportStatement:
implementVariableStatement
|implementFunctionStatement
;
// 实现协议
protocolImplementStatement:ProtocolSub nameSpace (templateCall)? BlockLeft (protocolImplementSupportStatement)* BlockRight Terminate;
// 变量实现
implementVariableStatement:expression Define expression Terminate;
// 函数实现
implementFunctionStatement:id (templateDefine)? Define t=(Function|FunctionAsync) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;

// 函数
functionStatement:id (templateDefine)? Define t=(Function|FunctionAsync) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 返回
returnStatement: ArrowRight '(' (expressionList)? ')' Terminate;
// 入参
parameterClauseIn : '(' parameter? (',' parameter)*  ')'  ;
// 出参
parameterClauseOut : '(' parameter? (',' parameter)*  ')'  ;
// 参数结构
parameter : id ':' type;
// 检查
checkStatement: Check BlockLeft (functionSupportStatement)* BlockRight checkErrorStatement Terminate;
// 错误处理
checkErrorStatement:Wave id BlockLeft (functionSupportStatement)* BlockRight;
// 报告错误
reportStatement: CheckSub (expression)? Terminate;

// 函数支持的语句
functionSupportStatement:
 returnStatement
| variableStatement
| judgeCaseStatement
| judgeStatement
| loopStatement
| loopEachStatement
| loopInfiniteStatement
| assignStatement
| expressionStatement
| checkStatement
| reportStatement
| functionStatement
;

logicStatement:
 returnStatement
| variableStatement
| judgeCaseStatement
| judgeStatement
| loopStatement
| loopEachStatement
| loopInfiniteStatement
| loopJumpStatement
| assignStatement
| expressionStatement
| checkStatement
| reportStatement
;
// 条件判断
judgeCaseStatement: Judge expression BlockLeft (caseStatement)+ BlockRight Terminate;
// 缺省条件声明
caseDefaultStatement: Wave Discard BlockLeft (logicStatement)* BlockRight Terminate;
// 条件声明
caseExprStatement: Wave expression BlockLeft (logicStatement)* BlockRight Terminate;
// 判断条件声明
caseStatement: caseDefaultStatement|caseExprStatement;
// 判断
judgeStatement:(judgeBaseStatement)+ (judgeElseStatement)? Terminate;
// 判断基础
judgeBaseStatement:Judge expression BlockLeft (logicStatement)* BlockRight;
// else 判断
judgeElseStatement:JudgeSub BlockLeft (logicStatement)* BlockRight;
// 循环
loopStatement:Loop iteratorStatement Wave id BlockLeft (logicStatement)* BlockRight Terminate;
// 集合循环
loopEachStatement:Loop expression Wave id BlockLeft (logicStatement)* BlockRight Terminate;
// 无限循环
loopInfiniteStatement:Loop BlockLeft (logicStatement)* BlockRight Terminate;
// 跳出循环
loopJumpStatement:LoopSub Terminate;
// 迭代器
iteratorStatement:Number '..' Number '..' Number | Number '..' Number;
// 命名空间
nameSpaceStatement:nameSpace Terminate;

// 定义变量
variableStatement: expression Define expression Terminate;
// 赋值
assignStatement: expression assign expression Terminate;

expressionStatement: expression Terminate;

// 基础表达式
primaryExpression: 
id
| t=Self
| t=Discard
| dataStatement
| '(' expression ')'
;

// 表达式
expression:
primaryExpression
| callFunc // 函数调用
| callPkg // 新建包
| callAwait // 异步调用
| array // 数组
| dictionary // 字典
| lambda // 匿名函数
| variableList // 变量列
| empty // 类型空初始化
| plusMinus // 正负处理
| expression as type // 类型转换
| expression is type // 类型判断
| expression readElement // 访问元素
| expression call expression // 链式调用
| expression judge expression // 判断型表达式
| expression add expression // 和型表达式
| expression mul expression // 积型表达式
;

expressionList : expression (',' expression)* ; // 表达式列

attribute: '\\' expressionList '\\'; // 属性

tuple : '(' (id ':' expression (',' id ':' expression)* )? ')'; // 元组

variableList : '(' expressionList ')' ; // 变量列

callFunc: id (templateCall)? tuple; // 函数调用

callPkg: type wave tuple; // 新建包

callAwait: FunctionAsync expression; // 异步调用

array : '[' (expression (',' expression)*)? ']'; // 数组

dictionary : '[' (dictionaryElement (',' dictionaryElement)*)? ']'; // 字典

dictionaryElement: expression ':' expression; // 字典元素

readElement : ('[' expression ']')+ ;

nameSpace: id ('.' id)* ;

templateDefine: '<' id (',' id)* '>';

templateCall: '<' type (',' type)* '>';

lambda : t=(Function|FunctionAsync) lambdaIn Wave lambdaOut;

lambdaIn : '(' (id (',' id)* )? ')'  ;
lambdaOut : '(' (functionSupportStatement)* ')'  ;

empty : '~<' type '>'; // 类型空初始化

plusMinus : add expression;

// 基础数据
dataStatement:
t=Number
| t=Text
| t=True
| t=False
| t=Nil
;
// 类型
type:
typeProtocol
| typeTuple
| typeArray
| typeDictinary
| typeBasic
| typePackage
| typeFunction
;

typeProtocol : Protocol nameSpace;
typeTuple : '(' type (',' type)+ ')';
typeArray : '[' type ']' ;
typeDictinary :  '[' type ':' type ']';
typePackage : nameSpace (templateCall)? ;
typeFunction : Function typeFunctionParameterClause Wave typeFunctionParameterClause;

// 函数类型参数
typeFunctionParameterClause : '(' (id ':' type (',' id ':' type)* )? ')'  ;

// 基础类型名
typeBasic:
t=TypeAny
| t=TypeNumber
| t=TypeText
| t=TypeBool
;

// bool值
bool:t=True|t=False;

as : op='!:';
is : op='?:';
judge : op=('||' | '&&' | '==' | '!=' | '<' | '>');
assign : op=('=' | '+=' | '-=' | '*=' | '/=' | '%=');
add : op=('+' | '-');
mul : op=('*' | '/' | '%');
call : op='.';
wave : op='~';

id: op=(IDPublic|IDPrivate)
|typeBasic;

Terminate : ';';

BlockLeft : '{';
BlockRight : '}';

Define : '=>';
Redefine: '<=';

Import : '<:';
Export : ':>';

SelfSub : '~^';
Self : '^';

ArrowRight : '->';
ArrowLeft : '<-';

JudgeSub : '~?';
Judge : '?';

LoopSub : '~@';
Loop : '@';

CheckSub : '~!';
Check : '!';

FunctionAsync : '.$';
Function : '$';

PackageSub : '~#';
Package : '#';

ProtocolSub : '~&';
Protocol : '&';

Wave : '~';

TypeAny : 'any';
TypeNumber: 'number';
TypeText: 'text';
TypeBool: 'bool';
True: 'true';
False: 'false';
Nil : 'nil';

Number :DIGIT+ ('.' DIGIT+)?; // 数字
fragment DIGIT : [0-9] ;             // 单个数字
Text: '"' (~[\\\r\n])*? '"'; // 文本
IDPrivate : '_' [a-zA-Z0-9]+; // 私有标识符
IDPublic  : [a-zA-Z] [a-zA-Z0-9]*; // 公有标识符
Discard : '_'; // 匿名变量

Comment : '/*' .*? '*/' -> skip; // 结构注释
CommentLine : '//' .*? '\r'? '\n' -> skip; // 行注释

//WS : ' ' -> skip;

WS   : [ \t\r\n]+ -> skip; // 空白， 后面的->skip表示antlr4在分析语言的文本时，符合这个规则的词法将被无视