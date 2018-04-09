grammar Xy;

program : statement+;

statement :exportStatement | sharpExportStatement;		  

// 导出命名空间
exportStatement:Export nameSpace BlockLeft (exportSupportStatement)* BlockRight Terminate;
// 导出命名空间支持的语句
exportSupportStatement:
importStatement
|packageStatement
|protocolStatement
|functionMainStatement
|namespaceFunctionStatement
|namespaceVariableStatement
|namespaceInvariableStatement
|namespaceControlStatement
|namespaceControlEmptyStatement
;
// dotnet 命名空间
sharpExportStatement: '#>' nameSpace BlockLeft (sharpExportSupportStatement)* BlockRight Terminate;
sharpExportSupportStatement:
importStatement
|packageStatement
|protocolStatement
;
// 导入命名空间
importStatement:Import BlockLeft (nameSpaceStatement)* BlockRight Terminate;
// 命名空间
nameSpaceStatement:(annotation)? (callNamespace)? nameSpace Terminate;
// 省略调用名称
callNamespace: '..';
// 主函数
functionMainStatement:Function BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 命名空间变量
namespaceVariableStatement:(annotation)? expression Define expression Terminate;
// 命名空间常量
namespaceInvariableStatement:(annotation)? expression '==' expression Terminate;
// 定义控制
namespaceControlStatement: (annotation)? id Define Control type (namespaceControlSubStatement)+ Terminate;
// 定义子方法
namespaceControlSubStatement: Wave id BlockLeft (functionSupportStatement)* BlockRight;
// 定义空控制
namespaceControlEmptyStatement:(annotation)? id Define Control type Terminate;
// 命名空间函数
namespaceFunctionStatement:(annotation)? id (templateDefine)? Define t=(Function|FunctionSub) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 定义包
packageStatement:(annotation)? id (templateDefine)? Define Package parameterClauseIn BlockLeft (packageSupportStatement)* BlockRight Terminate;
// 包支持的语句
packageSupportStatement:
packageStatement
|packageInitStatement
|packageExtend
|protocolStatement
|protocolImplementStatement
|packageFunctionStatement
|packageOverrideFunctionStatement
|packageControlStatement
|packageControlEmptyStatement
|packageVariableStatement
;
// 包构造方法
packageInitStatement:(annotation)? PackageSub BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 函数
packageFunctionStatement:(annotation)? id (templateDefine)? Define t=(Function|FunctionSub) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 重载函数
packageOverrideFunctionStatement:(annotation)? id Define '#$' parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 定义引入
packageExtend: PackageSub type Terminate;
// 定义变量
packageVariableStatement:(annotation)? expression Define expression Terminate;
// 定义控制
packageControlStatement: (annotation)? id Define Control type (packageControlSubStatement)+ Terminate;
// 定义子方法
packageControlSubStatement: Wave id BlockLeft (functionSupportStatement)* BlockRight;
// 定义空控制
packageControlEmptyStatement:(annotation)? id Define Control type Terminate;

// 协议
protocolStatement:(annotation)? id (templateDefine)? Define Protocol BlockLeft (protocolSupportStatement)* BlockRight Terminate;
// 协议支持的语句
protocolSupportStatement:
protocolStatement
|protocolFunctionStatement
|protocolControlStatement
|protocolControlEmptyStatement
;
// 定义控制
protocolControlStatement:(annotation)? id Define Control type (protocolControlSubStatement)+ Terminate;
// 定义子方法
protocolControlSubStatement: Wave id;
// 定义空控制
protocolControlEmptyStatement: (annotation)? id Define Control type Terminate;
// 函数
protocolFunctionStatement:(annotation)? id (templateDefine)? Define t=(Function|FunctionSub) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 协议实现支持的语句
protocolImplementSupportStatement:
implementFunctionStatement
|implementControlStatement
|implementControlEmptyStatement
|implementEventStatement
;
// 实现协议
protocolImplementStatement:ProtocolSub nameSpace (templateCall)? BlockLeft (protocolImplementSupportStatement)* BlockRight Terminate;
// 控制实现
implementControlStatement:(annotation)? id Define Control type (packageControlSubStatement)+ Terminate;
// 空控制实现
implementControlEmptyStatement: (annotation)? id Define Control type Terminate;
// 函数实现
implementFunctionStatement:(annotation)? id (templateDefine)? Define t=(Function|FunctionSub) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 事件实现
implementEventStatement: id Define '#!' nameSpace Terminate;
// 函数
functionStatement:id (templateDefine)? Define t=(Function|FunctionSub) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 返回
returnStatement: ArrowRight tuple Terminate;
// 入参
parameterClauseIn : '(' parameter? (',' parameter)*  ')'  ;
// 出参
parameterClauseOut : '(' parameter? (',' parameter)*  ')'  ;
// 参数结构
parameter :(annotation)? id ':' type;

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
checkDeferStatement: CheckSub BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 检查
checkStatement: Check BlockLeft (functionSupportStatement)* BlockRight checkErrorStatement Terminate;
// 错误处理
checkErrorStatement:Wave id BlockLeft (functionSupportStatement)* BlockRight;
// 报告错误
reportStatement: CheckReport (expression)? Terminate;
// 迭代器
iteratorStatement: '[' expression Wave expression Terminate expression ']' | '[' expression Wave expression ']';

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
| callSelf // 调用自己
| callFunc // 函数调用
| callPkg // 新建包
| getType // 获取类型
| callAwait // 异步调用
| basicConvert // 基础数据转化
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

callSelf: '..' callExpression;

callExpression:
callElement // 访问元素
| callIs // 类型判断
| callAs // 类型转换
| callFunc // 函数调用
| callPkg // 新建包
| id // id
| callExpression call callExpression // 链式调用
;

tuple : '(' (expression (',' expression)* )? ')'; // 元组

expressionList : expression (',' expression)* ; // 表达式列

annotation: '\\*' expressionList '*\\'; // 注解

callFunc: id (templateCall)? call tuple; // 函数调用

callPkg: '#' type call tuple (pkgAssign|arrayAssign|dictionaryAssign)?; // 新建包

getType: '#' type;

pkgAssign: BlockLeft (pkgAssignElement (',' pkgAssignElement)*)? BlockRight; // 简化赋值

pkgAssignElement: nameSpace ':' expression; // 简化赋值元素

arrayAssign: '[' (expression (',' expression)*)? ']';

dictionaryAssign: '[' (dictionaryElement (',' dictionaryElement)*)?  ']';

callIs: is type ':'?; // 类型判断

callAs: as type ':'?; // 类型转换

callAwait: FunctionSub expression; // 异步调用

basicConvert: typeBasic '(' expression ')'; // 基础数据转换

array : '[' (expression (',' expression)*)? ']'; // 数组

sharpArray : '[' '#' ']' '[' (expression (',' expression)*)? ']'; // c#数组

dictionary :  '[' (dictionaryElement (',' dictionaryElement)*)?  ']'; // 字典

dictionaryElement: expression ':' expression; // 字典元素

callElement : '[' expression ']';

nameSpace: id ('.' id)* ;

templateDefine: '<' id (',' id)* '>';

templateCall: '<' type (',' type)* '>';

lambda : t=(Function|FunctionSub) lambdaIn ArrowRight lambdaOut;

lambdaIn : (id (',' id)* )? ;
lambdaOut : expressionList ;

package: Package pkgAssign; // 匿名包

function : t=(Function|FunctionSub) parameterClauseIn Wave parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight;

empty : '~:' type; // 类型空初始化

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
| t=TypeStr
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

Self : '..';

ArrowRight : '->';
ArrowLeft : '<-';

JudgeSub : '~?';
Judge : '?';

LoopSub : '~@';
Loop : '@';

CheckReport : '!~' ;
CheckSub : '~!';
Check : '!';

FunctionSub : '~$';
Function : '$';

Control : '^';

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
TypeStr: 'str';
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