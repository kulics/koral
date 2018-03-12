grammar Xy;

program : statement+;

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
packageStatement:(annotation)? id (templateDefine)? Define Package Wave parameterClauseIn BlockLeft (packageSupportStatement)* BlockRight Terminate;
// 包支持的语句
packageSupportStatement:
packageStatement
|packageInitStatement
|packageExtend
|protocolStatement
|protocolImplementStatement
|packageFunctionStatement
|packageVariableStatement
;
// 包构造方法
packageInitStatement:PackageSub BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 函数
packageFunctionStatement:id (templateDefine)? Define t=(Function|FunctionAsync) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 定义引入
packageExtend: PackageSub nameSpace Terminate;
// 定义变量
packageVariableStatement:(annotation)? expression Define expression Terminate;

// 协议
protocolStatement: id (templateDefine)? Define Protocol BlockLeft (protocolSupportStatement)* BlockRight Terminate;
// 协议支持的语句
protocolSupportStatement:
protocolStatement
|protocolFunctionStatement
|protocolVariableStatement
;
// 定义变量
protocolVariableStatement:expression Define expression Terminate;
// 函数
protocolFunctionStatement:id (templateDefine)? Define t=(Function|FunctionAsync) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 协议实现支持的语句
protocolImplementSupportStatement:
implementFunctionStatement
|implementVariableStatement
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
returnStatement: ArrowRight tuple Terminate;
// 入参
parameterClauseIn : '(' parameter? (',' parameter)*  ')'  ;
// 出参
parameterClauseOut : '(' parameter? (',' parameter)*  ')'  ;
// 参数结构
parameter : id ':' type;

// 函数支持的语句
functionSupportStatement:
 returnStatement
| judgeCaseStatement
| judgeStatement
| loopStatement
| loopEachStatement
| loopInfiniteStatement
| loopJumpStatement
| checkDeferStatement
| checkStatement
| reportStatement
| functionStatement
| variableStatement
| assignStatement
| expressionStatement
;

// 条件判断
judgeCaseStatement: Judge expression (caseStatement)+ Terminate;
// 缺省条件声明
caseDefaultStatement: Wave Discard BlockLeft (functionSupportStatement)* BlockRight;
// 条件声明
caseExprStatement: Wave expression BlockLeft (functionSupportStatement)* BlockRight;
// 判断条件声明
caseStatement: caseDefaultStatement|caseExprStatement;
// 判断
judgeStatement:(judgeBaseStatement)+ (judgeElseStatement)? Terminate;
// 判断基础
judgeBaseStatement:Judge expression BlockLeft (functionSupportStatement)* BlockRight;
// else 判断
judgeElseStatement:JudgeSub BlockLeft (functionSupportStatement)* BlockRight;
// 循环
loopStatement:Loop iteratorStatement Wave id BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 集合循环
loopEachStatement:Loop expression Wave id BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 无限循环
loopInfiniteStatement:Loop BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 跳出循环
loopJumpStatement:LoopSub Terminate;
// 看守
checkDeferStatement: CheckDefer BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 检查
checkStatement: Check BlockLeft (functionSupportStatement)* BlockRight checkErrorStatement Terminate;
// 错误处理
checkErrorStatement:Wave id BlockLeft (functionSupportStatement)* BlockRight;
// 报告错误
reportStatement: CheckSub (expression)? Terminate;
// 迭代器
iteratorStatement:expression '..' expression '..' expression | expression '..' expression;
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
| callIs // 类型判断
| callAs // 类型转换
| sharpArray // c#数组
| array // 数组
| dictionary // 字典
| lambda // lambda表达式
| function // 函数
| package // 匿名包
| tuple // 元组
| empty // 类型空初始化
| plusMinus // 正负处理
| negate // 取反
| linq // 联合查询
| expression call callExpression // 链式调用
| expression judge expression // 判断型表达式
| expression add expression // 和型表达式
| expression mul expression // 积型表达式
;

callExpression:
callElement // 访问元素
| callFunc // 函数调用
| callPkg // 新建包
| id // id
| callExpression call callExpression // 链式调用
;

tuple : '(' (expression (',' expression)* )? ')'; // 元组

expressionList : expression (',' expression)* ; // 表达式列

annotation: '\\*' expressionList '*\\'; // 注解

callFunc: id (templateCall)? tuple; // 函数调用

callPkg: type wave tuple (pkgAssign)?; // 新建包

pkgAssign: BlockLeft (pkgAssignElement (',' pkgAssignElement)*)? BlockRight; // 简化赋值

pkgAssignElement: nameSpace ':' expression; // 简化赋值元素

callIs: type is '(' expression ')'; // 类型判断

callAs: type as '(' expression ')';	// 类型转换

callAwait: FunctionAsync expression; // 异步调用

array : '[' (expression (',' expression)*)? ']'; // 数组

sharpArray : '[' '#' ']' '[' (expression (',' expression)*)? ']'; // c#数组

dictionary :  '[' (dictionaryElement (',' dictionaryElement)*)?  ']'; // 字典

dictionaryElement: expression ':' expression; // 字典元素

callElement : '[' expression ']';

nameSpace: id ('.' id)* ;

templateDefine: '<' id (',' id)* '>';

templateCall: '<' type (',' type)* '>';

lambda : t=(Function|FunctionAsync) lambdaIn Wave lambdaOut;

lambdaIn : '(' (id (',' id)* )? ')';
lambdaOut : '(' expressionList ')';

package: Package pkgAssign; // 匿名包

function : t=(Function|FunctionAsync) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight;

empty : '~<' type '>'; // 类型空初始化

plusMinus : add expression;

negate : '~~' expression;

linq: '`' (linqItem)+  '`';

linqItem: linqKeyword|expression;

linqKeyword: k=('from'|'where'|'select'|'group'|'into'|'orderby'|'join'|'let'|'in'|'on'|'equals'|'by'|'ascending'|'descending') ;

// 基础数据
dataStatement:
t=Float
| t=Integer
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
| typeSharpArray
| typeDictinary
| typeBasic
| typePackage
| typeFunction
;

typeProtocol : Protocol nameSpace;
typeTuple : '(' type (',' type)+ ')';
typeArray : '[' ']' type;
typeSharpArray :'[' '#' ']' type;
typeDictinary :  '[' type ']' type;
typePackage : nameSpace (templateCall)? ;
typeFunction : Function typeFunctionParameterClause Wave typeFunctionParameterClause;

// 函数类型参数
typeFunctionParameterClause : '(' (id ':' type (',' id ':' type)* )? ')'  ;

// 基础类型名
typeBasic:
t=TypeAny
| t=TypeI8
| t=TypeU8
| t=TypeI16
| t=TypeU16
| t=TypeI32
| t=TypeU32
| t=TypeI64
| t=TypeU64
| t=TypeF32
| t=TypeF64
| t=TypeText
| t=TypeBool
;

// bool值
bool:t=True|t=False;

as : op='!';
is : op='?';
judge : op=('||' | '&&' | '=' | '!=' | '<' | '>');
assign : op=(Assign | '+=' | '-=' | '*=' | '/=' | '%=');
add : op=('+' | '-');
mul : op=('*' | '/' | '%');
call : op='.';
wave : op='~';

id: op=(IDPublic|IDPrivate)
|typeBasic
|linqKeyword;

Terminate : ';';

BlockLeft : '{';
BlockRight : '}';

Define : '=>';
Assign: '<=';

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

CheckDefer : '.!';
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
TypeI8: 'i8';
TypeU8: 'u8';
TypeI16: 'i16';
TypeU16: 'u16';
TypeI32: 'i32';
TypeU32: 'u32';
TypeI64: 'i64';
TypeU64: 'u64';
TypeF32: 'f32';
TypeF64: 'f64';
TypeText: 'txt';
TypeBool: 'bool';
True: 'true';
False: 'false';
Nil : 'nil';

Float: Integer '.' DIGIT+ ; // 浮点数
Integer : DIGIT+ ; // 整数
fragment DIGIT : [0-9] ;             // 单个数字
Text: '"' (~[\\\r\n])*? '"'; // 文本
IDPrivate : '_' [a-zA-Z0-9_]+; // 私有标识符
IDPublic  : [a-zA-Z] [a-zA-Z0-9_]*; // 公有标识符
Discard : '_'; // 匿名变量

Comment : '/*' .*? '*/' -> skip; // 结构注释
CommentLine : '//' .*? '\r'? '\n' -> skip; // 行注释

//WS : ' ' -> skip;

WS   : [ \t\r\n]+ -> skip; // 空白， 后面的->skip表示antlr4在分析语言的文本时，符合这个规则的词法将被无视