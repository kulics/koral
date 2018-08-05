grammar Xy;

program : statement+;

statement :exportStatement;		  

// 导出命名空间
exportStatement: nameSpace (importStatement)? BlockLeft (exportSupportStatement)* BlockRight Terminate;
// 导出命名空间支持的语句
exportSupportStatement:
functionMainStatement
|nspackageStatement
|packageStatement
|protocolStatement
|enumStatement
;
// 导入命名空间
importStatement: (nameSpaceStatement)*;
// 命名空间
nameSpaceStatement: Wave (annotation)? (callEllipsis)? (nameSpace)? (call id)?;
// 省略调用名称
callEllipsis: '..';
// 枚举
enumStatement: (annotation)? id Package '[' enumSupportStatement (',' enumSupportStatement)* ']' Terminate;

enumSupportStatement: id ('=' (add)? Integer)?;

// 无构造包
nspackageStatement: (annotation)? id (templateDefine)? Package BlockLeft (nspackageSupportStatement)* BlockRight Terminate;

nspackageSupportStatement:
nspackageFunctionStatement
|nspackageVariableStatement
|nspackageInvariableStatement
;

// 主函数
functionMainStatement:Function BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 无构造包变量
nspackageVariableStatement:(annotation)? expression (Define expression|Declared type (Assign expression)?) (nspackageControlSubStatement)* Terminate;
// 无构造包常量
nspackageInvariableStatement:(annotation)? expression (Declared type '==' | ':==') expression Terminate;
// 定义子方法
nspackageControlSubStatement: Control id (BlockLeft (functionSupportStatement)* BlockRight)?;
// 无构造包函数
nspackageFunctionStatement:(annotation)? id (templateDefine)? Function parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 定义包
packageStatement:(annotation)? id (templateDefine)? Package parameterClausePackage (extend)? BlockLeft (packageSupportStatement)* BlockRight Terminate;
// 继承
extend: ':' type '{' expressionList? '}';
// 入参
parameterClausePackage : '{' parameter? (',' parameter)*  '}'  ;
// 包支持的语句
packageSupportStatement:
packageInitStatement
|protocolStatement
|protocolImplementStatement
|packageFunctionStatement
|packageOverrideFunctionStatement
|packageVariableStatement
;
// 包构造方法
packageInitStatement:(annotation)? Package BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 函数
packageFunctionStatement:(annotation)? id (templateDefine)? Function parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 重载函数
packageOverrideFunctionStatement:(annotation)? Self id Function parameterClauseIn ArrowRight parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 定义变量
packageVariableStatement:(annotation)? expression (Define expression|Declared type (Assign expression)?) (packageControlSubStatement)* Terminate;
// 定义子方法
packageControlSubStatement: Control id (BlockLeft (functionSupportStatement)* BlockRight)?;

// 协议
protocolStatement:(annotation)? id (templateDefine)? Protocol BlockLeft (protocolSupportStatement)* BlockRight Terminate;
// 协议支持的语句
protocolSupportStatement:
protocolStatement
|protocolFunctionStatement
|protocolControlStatement
;
// 定义控制
protocolControlStatement:(annotation)? id Declared type (protocolControlSubStatement)* Terminate;
// 定义子方法
protocolControlSubStatement: Control id;
// 函数
protocolFunctionStatement:(annotation)? id (templateDefine)? Function parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 协议实现支持的语句
protocolImplementSupportStatement:
implementFunctionStatement
|implementControlStatement
|implementEventStatement
;
// 实现协议
protocolImplementStatement:Protocol nameSpaceItem (templateCall)? BlockLeft (protocolImplementSupportStatement)* BlockRight Terminate;
// 控制实现
implementControlStatement:(annotation)? id (Define expression|Declared type (Assign expression)?) (packageControlSubStatement)* Terminate;
// 函数实现
implementFunctionStatement:(annotation)? id (templateDefine)? Function parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 事件实现
implementEventStatement: id '^!' nameSpaceItem Terminate;
// 函数
functionStatement:id (templateDefine)? Function parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 返回
returnStatement: ArrowLeft tuple Terminate;
// 入参
parameterClauseIn : '(' parameter? (',' parameter)*  ')'  ;
// 出参
parameterClauseOut : '(' parameter? (',' parameter)*  ')'  ;
// 参数结构
parameter :(annotation)? id (':' type)?;

// 函数支持的语句
functionSupportStatement:
 returnStatement
| judgeCaseStatement
| judgeStatement
| loopStatement
| loopEachStatement
| loopCaseStatement
| loopInfiniteStatement
| loopJumpStatement
| checkDeferStatement
| checkStatement
| reportStatement
| functionStatement
| variableStatement
| variableDeclaredStatement
| assignStatement
| variableUseStatement
| expressionStatement
;

// 条件判断
judgeCaseStatement: expression call Judge (caseStatement)+ Terminate;
// 缺省条件声明
caseDefaultStatement: Discard BlockLeft (functionSupportStatement)* BlockRight;
// 条件声明
caseExprStatement: (expression| (id)? ':' type) BlockLeft (functionSupportStatement)* BlockRight;
// 判断条件声明
caseStatement: caseDefaultStatement|caseExprStatement;
// 判断
judgeStatement:(judgeBaseStatement)+ (judgeElseStatement)? Terminate;
// 判断基础
judgeBaseStatement:Judge expression BlockLeft (functionSupportStatement)* BlockRight;
// else 判断
judgeElseStatement:Judge BlockLeft (functionSupportStatement)* BlockRight;
// 循环
loopStatement:iteratorStatement call Loop (id)? BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 集合循环
loopEachStatement:expression call Loop (id)? BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 条件循环
loopCaseStatement:Loop expression BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 无限循环
loopInfiniteStatement:Loop BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 跳出循环
loopJumpStatement:LoopSub Terminate;
// 看守
checkDeferStatement: CheckSub BlockLeft (functionSupportStatement)* BlockRight Terminate;
// 检查
checkStatement: Check BlockLeft (functionSupportStatement)* BlockRight checkErrorStatement+ Terminate;
// 错误处理
checkErrorStatement:id (Declared type)? BlockLeft (functionSupportStatement)* BlockRight;
// 报告错误
reportStatement: Check call '(' (expression)? ')' Terminate;
// 迭代器
iteratorStatement: '[' expression Wave expression Terminate expression ']' | '[' expression Wave expression ']';

// 定义变量
variableStatement: expression Define expression Terminate;
// 声明变量
variableDeclaredStatement: expression Declared type (Assign expression)? Terminate;
// 赋值
assignStatement: expression assign expression Terminate;
// 定义回收变量
variableUseStatement: expression Use expression Terminate;

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
| basicConvert // 基础数据转化
| callSelf // 调用自己
| callNameSpace // 调用命名空间
| callFunc // 函数调用
| callPkg // 新建包
| getType // 获取类型
| callAwait // 异步调用
| sharpArray // c#数组
| array // 数组
| dictionary // 字典
| lambda // lambda表达式
| function // 函数
| pkgAnonymous // 匿名包
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
callNameSpace: ('\\' id)+ call callExpression;

callExpression:
callElement // 访问元素
| callIs // 类型判断
| callAs // 类型转换
| callFunc // 函数调用
| callPkg // 新建包
| id // id
| callExpression call callExpression // 链式调用
;

basicConvert: typeBasic call '(' expression ')'; // 基础数据转换

tuple : '(' (expression (',' expression)* )? ')'; // 元组

expressionList : expression (',' expression)* ; // 表达式列

annotation: '\\\\' (id ':')? annotationList | '\\*' (id ':')? annotationList '*\\' ; // 注解

annotationList: annotationItem (',' annotationItem)*;

annotationItem: id ('.' '{' annotationAssign (',' annotationAssign)* '}')? ;

annotationAssign: (id '=')? expression ;

callFunc: id (templateCall)? call tuple; // 函数调用

callPkg: type call '{' expressionList? ( '...' (pkgAssign|arrayAssign|dictionaryAssign))? '}'; // 新建包

getType: Judge call '(' (expression|':' type) ')';

pkgAssign: (pkgAssignElement (',' pkgAssignElement)*)? ; // 简化赋值

pkgAssignElement: name Assign expression; // 简化赋值元素

arrayAssign: (expression (',' expression)*)? ;

dictionaryAssign: (dictionaryElement (',' dictionaryElement)*)? ;

callIs: is type; // 类型判断

callAs: as type; // 类型转换

callAwait: FlowLeft expression; // 异步调用

array : '[' (expression (',' expression)*)? ']'; // 数组

sharpArray : '[' '#' ']' '[' (expression (',' expression)*)? ']'; // c#数组

dictionary :  '[' (dictionaryElement (',' dictionaryElement)*)?  ']'; // 字典

dictionaryElement: expression '->' expression; // 字典元素

callElement : '[' expression ']';

nameSpace: id ('\\' id)*;

nameSpaceItem: (('\\' id)+ call)? id;

name: id (call id)* ;

templateDefine: '<' id (',' id)* '>';

templateCall: '<' type (',' type)* '>';

lambda : Function lambdaIn t=(ArrowLeft|FlowLeft) lambdaOut;

lambdaIn : (id (',' id)* )? ;
lambdaOut : 
expressionList 
| BlockLeft (functionSupportStatement)* BlockRight;

pkgAnonymous: Package pkgAnonymousAssign; // 匿名包

pkgAnonymousAssign: BlockLeft (pkgAnonymousAssignElement)* BlockRight; // 简化赋值

pkgAnonymousAssignElement: name ':=' expression Terminate; // 简化赋值元素

function : Function parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight;

empty : Null call '(' type ')'; // 类型空初始化

plusMinus : add expression;

negate : '~' expression;

linq: '`' (linqItem)+  '`';

linqItem: linqKeyword|expression;

linqKeyword: k=('from'|'where'|'select'|'group'|'into'|'orderby'|'join'|'let'|'in'|'on'|'equals'|'by'|'ascending'|'descending') ;

// 基础数据
dataStatement:
markText
| t=Float
| t=Integer
| t=Text
| t=True
| t=False
| t=Null
;

markText: '/' t=Text '/';

// 类型
typeNotNull:
typeTuple
| typeArray
| typeSharpArray
| typeDictinary
| typeBasic
| typePackage
| typeFunction
;

typeNullable : typeNotNull '?';
type : typeNotNull | typeNullable;

typeTuple : '(' type (',' type)+ ')';
typeArray : '[' ']' type;
typeSharpArray :'[' '#' ']' type;
typeDictinary :  '[' type ']' type;
typePackage : nameSpaceItem (templateCall)? ;
typeFunction : typeFunctionParameterClause ArrowRight typeFunctionParameterClause;

// 函数类型参数
typeFunctionParameterClause : '(' typeParameter? (',' typeParameter)*  ')';
// 参数结构
typeParameter :id (':' type)?;

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

as : op='!:';
is : op='?:';
judge : op=('||' | '&&' | '==' | '~=' | '<' | '>' | '<=' | '>=');
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

Define : ':=';
Declared : ':';
Assign: '=';
Use : '!=';

Self : '..';

ArrowRight : '->';
ArrowLeft : '<-';

FlowRight : '~>';
FlowLeft : '<~';

JudgeSub : '~?';
Judge : '?';

LoopSub : '~@';
Loop : '@';

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
Null : 'null';

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