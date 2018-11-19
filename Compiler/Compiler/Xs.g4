grammar Xs;

program: statement+;

statement: exportStatement namespaceSupportStatement*;

// 导出命名空间
exportStatement: nameSpace ('=' id)? BlockLeft (importStatement)* BlockRight Terminate?;

// 导入命名空间
importStatement: (annotation)? nameSpace (call id)? Terminate?;

namespaceSupportStatement:
namespaceFunctionStatement
|namespaceVariableStatement
|namespaceInvariableStatement
|namespaceConstantStatement
|packageStatement
|packageExtensionStatement
|protocolStatement
|protocolImplementStatement
|enumStatement
;

// 枚举
enumStatement: (annotation)? id '[' enumSupportStatement (',' enumSupportStatement)* ']' Terminate?;

enumSupportStatement: id ('=' (add)? Integer)?;

// 命名空间变量
namespaceVariableStatement:(annotation)? expression (Define expression|Declared type (Assign expression)?) (BlockLeft (namespaceControlSubStatement)* BlockRight)? Terminate?;
// 命名空间不变量
namespaceInvariableStatement:(annotation)? expression (Declared type '==' | ':==') expression Terminate?;
// 命名空间常量
namespaceConstantStatement: (annotation)? id (Declared type)? expression Terminate?;
// 定义子方法
namespaceControlSubStatement: id BlockLeft (functionSupportStatement)* BlockRight;
// 命名空间函数
namespaceFunctionStatement:(annotation)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight;
// 定义包
packageStatement:(annotation)? id (templateDefine)? parameterClausePackage ArrowRight (extend)? BlockLeft (packageSupportStatement)* BlockRight;
// 继承
extend: type '{' expressionList? '}';
// 入参
parameterClausePackage : '{' parameterPackage? (',' parameterPackage)*  '}'  ;
// 构造参数
parameterPackage : parameter|parameterSelf;
// 参数结构
parameterSelf : (annotation)? '..' id (':' type)?;
// 包支持的语句
packageSupportStatement:
packageInitStatement
|packageOverrideFunctionStatement
|packageVariableStatement
;
// 包构造方法
packageInitStatement:(annotation)? '..' BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 函数
packageFunctionStatement:(annotation)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 重载函数
packageOverrideFunctionStatement:(annotation)? Self id parameterClauseIn ArrowRight parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 定义变量
packageVariableStatement:(annotation)? expression (Define expression|Declared type (Assign expression)?) (BlockLeft (packageControlSubStatement)* BlockRight)? Terminate?;
// 定义子方法
packageControlSubStatement: id BlockLeft (functionSupportStatement)* BlockRight;
// 包扩展
packageExtensionStatement: id (templateDefine)? '+=' BlockLeft (packageExtensionSupportStatement)* BlockRight Terminate?;
// 包扩展支持的语句
packageExtensionSupportStatement: packageFunctionStatement;
// 协议
protocolStatement:(annotation)? id (templateDefine)? ArrowRight BlockLeft (protocolSupportStatement)* BlockRight Terminate?;
// 协议支持的语句
protocolSupportStatement:
protocolStatement
|protocolFunctionStatement
|protocolControlStatement
;
// 定义控制
protocolControlStatement:(annotation)? id Declared type (BlockLeft (protocolControlSubStatement)* BlockRight)? Terminate?;
// 定义子方法
protocolControlSubStatement: id BlockLeft BlockRight;
// 函数
protocolFunctionStatement:(annotation)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 协议实现支持的语句
protocolImplementSupportStatement:
implementFunctionStatement
|implementControlStatement
|implementEventStatement
;
// 实现协议
protocolImplementStatement: id '+=' nameSpaceItem (templateCall)? BlockLeft (protocolImplementSupportStatement)* BlockRight Terminate?;
// 控制实现
implementControlStatement:(annotation)? id (Define expression|Declared type (Assign expression)?) (BlockLeft (packageControlSubStatement)* BlockRight)? Terminate?;
// 函数实现
implementFunctionStatement:(annotation)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 事件实现
implementEventStatement: id 'event' nameSpaceItem Terminate?;
// 函数
functionStatement:id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 返回
returnStatement: ArrowLeft tuple Terminate?;
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
| loopContinueStatement
| checkStatement
| reportStatement
| functionStatement
| variableStatement
| variableDeclaredStatement
| assignStatement
| execFuncStatement
;

// 条件判断
judgeCaseStatement: Judge expression ArrowRight (caseStatement)+ Terminate?;
// 缺省条件声明
caseDefaultStatement: Discard BlockLeft (functionSupportStatement)* BlockRight;
// 条件声明
caseExprStatement: (expression| (id)? ':' type) BlockLeft (functionSupportStatement)* BlockRight;
// 判断条件声明
caseStatement: caseDefaultStatement|caseExprStatement;
// 判断
judgeStatement:
judgeIfStatement (judgeElseIfStatement)* judgeElseStatement Terminate?
| judgeIfStatement (judgeElseIfStatement)* Terminate?;
// else 判断
judgeElseStatement:Discard BlockLeft (functionSupportStatement)* BlockRight;
// if 判断
judgeIfStatement:Judge expression BlockLeft (functionSupportStatement)* BlockRight;
// else if 判断
judgeElseIfStatement: expression BlockLeft (functionSupportStatement)* BlockRight;
// 循环
loopStatement:Loop iteratorStatement (id)? BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 集合循环
loopEachStatement:Loop '[' expression ']' ((id ArrowRight)? id)? BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 条件循环
loopCaseStatement:Loop expression BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 无限循环
loopInfiniteStatement:Loop BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 跳出循环
loopJumpStatement:ArrowLeft Loop Terminate?;
// 跳出当前循环
loopContinueStatement:ArrowRight Loop Terminate?;
// 检查
checkStatement: 
Check usingExpression BlockLeft (functionSupportStatement)* BlockRight Terminate?
|Check (usingExpression)? BlockLeft (functionSupportStatement)* BlockRight (checkErrorStatement)* checkFinallyStatment Terminate?
|Check (usingExpression)? BlockLeft (functionSupportStatement)* BlockRight (checkErrorStatement)+ Terminate?;
// 定义变量
usingExpression: expression (Define|Declared type Assign) expression;
// 错误处理
checkErrorStatement:(id|Declared type) BlockLeft (functionSupportStatement)* BlockRight;
// 最终执行
checkFinallyStatment: Discard BlockLeft (functionSupportStatement)* BlockRight;

// 报告错误
reportStatement: Check '(' (expression)? ')' Terminate?;
// 迭代器
iteratorStatement: '[' expression op=('<'|'<='|'>'|'>=') expression Terminate expression ']' | '[' expression op=('<'|'<='|'>'|'>=') expression ']';

// 定义变量
variableStatement: expression (Define|Declared type Assign) expression Terminate?;
// 声明变量
variableDeclaredStatement: expression Declared type Terminate?;
// 赋值
assignStatement: expression assign expression Terminate?;

execFuncStatement: FlowLeft? (expression '.')? callFunc Terminate?;

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
linq // 联合查询
| primaryExpression
| callSelf // 调用自己
| callNameSpace // 调用命名空间
| callFunc // 函数调用
| callElement //调用元素
| callPkg // 新建包
| getType // 获取类型
| callAwait // 异步调用
| array // 数组
| list // 列表
| dictionary // 字典
| lambda // lambda表达式
| function // 函数
| pkgAnonymous // 匿名包
| tuple // 元组
| empty // 类型空初始化
| plusMinus // 正负处理
| negate // 取反
| expression call callExpression // 链式调用
| expression judge expression // 判断型表达式
| expression add expression // 和型表达式
| expression mul expression // 积型表达式
;

callSelf: '..' callExpression;
callNameSpace: ('\\' id)+ call callExpression;

callExpression:
callElement // 访问元素
| callFunc // 函数调用
| callPkg //
| id // id
| callExpression call callExpression // 链式调用
;

tuple : '(' (expression (',' expression)* )? ')'; // 元组

tupleExpression : '(' expression (',' expression)*  ')'; // 元组

expressionList : expression (',' expression)* ; // 表达式列

annotation: '`' (id ':')? annotationList '`' ; // 注解

annotationList: annotationItem (',' annotationItem)*;

annotationItem: id ( '{' annotationAssign (',' annotationAssign)* '}')? ;

annotationAssign: (id '=')? expression ;

callFunc: id (templateCall)? tuple; // 函数调用

callElement : id '[' (expression | slice) ']';

callPkg: type '{' expressionList? ( ArrowLeft (pkgAssign|listAssign|dictionaryAssign))? '}'; // 新建包

getType: Judge '(' (expression|':' type) ')';

pkgAssign: (pkgAssignElement (',' pkgAssignElement)*)? ; // 简化赋值

pkgAssignElement: name Assign expression; // 简化赋值元素

listAssign: (expression (',' expression)*)? ;

dictionaryAssign: (dictionaryElement (',' dictionaryElement)*)? ;

callAwait: FlowLeft expression; // 异步调用

array : '_{|' (expression (',' expression)*)? (':' type)? '|}'; // 数组

list : '_{' (expression (',' expression)*)? (':' type)? '}'; // 列表

dictionary :  '_{' (dictionaryElement (',' dictionaryElement)*)? (':' type '->' type)? '}'; // 字典

dictionaryElement: expression '->' expression; // 字典元素

slice: sliceFull | sliceStart | sliceEnd;

sliceFull: expression op=('<'|'<='|'>'|'>=') expression; 
sliceStart: expression op=('<'|'<='|'>'|'>=');
sliceEnd: op=('<'|'<='|'>'|'>=') expression; 

nameSpace: id ('\\' id)*;

nameSpaceItem: (('\\' id)+ call)? id;

name: id (call id)* ;

templateDefine: '<' id (',' id)* '>';

templateCall: '<' type (',' type)* '>';

lambda : '$' (lambdaIn)? t=(ArrowRight|FlowRight) expressionList 
| '$' BlockLeft (lambdaIn)? t=(ArrowRight|FlowRight) (functionSupportStatement)* BlockRight
| lambdaShort;

lambdaIn : id (',' id)*;

lambdaShort : '$' expressionList;

pkgAnonymous: pkgAnonymousAssign; // 匿名包

pkgAnonymousAssign: '_{' (pkgAnonymousAssignElement)+ BlockRight; // 简化赋值

pkgAnonymousAssignElement: name ':=' expression Terminate?; // 简化赋值元素

function : '_' parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight;

empty : Null call '(' type ')'; // 类型空初始化

plusMinus : add expression;

negate : wave expression;

linq: linqHeadKeyword expression (linqItem)+ k=('by'|'select') expression;

linqItem: linqBodyKeyword | expression;

linqKeyword: linqHeadKeyword | linqBodyKeyword ;
linqHeadKeyword: k='from';
linqBodyKeyword: k=('where'|'select'|'group'|'into'|'orderby'|'join'|'let'|'in'|'on'|'equals'|'by'|'ascending'|'descending') ;

// 基础数据
dataStatement:
t=Float
| t=Integer
| t=Text
| t=Char
| t=True
| t=False
| t=Null
;

// 类型
typeNotNull:
typeTuple
| typeList
| typeArray
| typeDictionary
| typeBasic
| typePackage
| typeFunction
;

typeNullable : typeNotNull '|' Null;
type : typeNotNull | typeNullable;

typeTuple : '(' type (',' type)+ ')';
typeList : '[' ']' type;
typeArray : '[' '|' ']' type;
typeDictionary :  '[' type ']' type;
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
| t=TypeChr
| t=TypeStr
| t=TypeBool
;

// bool值
bool:t=True|t=False;

as : op='?!';
is : op='?:';
judge : op=('|' | '&' | '==' | '~=' | '<' | '>' | '<=' | '>=');
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

Self : '..';

ArrowRight : '->';
ArrowLeft : '<-';

FlowRight : '~>';
FlowLeft : '<~';

Judge : '?';

Loop : '@';

Check : '!';

TypeAny : 'obj';
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
TypeChr: 'chr';
TypeStr: 'str';
TypeBool: 'bl';
True: 'true';
False: 'false';
Null : 'null';

Float: Integer '.' DIGIT+ ; // 浮点数
Integer : DIGIT+ ; // 整数
fragment DIGIT : [0-9] ;             // 单个数字
Text: '"' (~[\\\r\n])*? '"'; // 文本
Char: '\'' (~[\\\r\n])*? '\''; // 单字符
IDPrivate : '_' [a-zA-Z0-9_]+; // 私有标识符
IDPublic  : [a-zA-Z] [a-zA-Z0-9_]*; // 公有标识符
Discard : '_'; // 匿名变量

// Comment : '/*' .*? '*/' -> skip; // 结构注释
CommentLine : '#' .*? '\r'? '\n' -> skip; // 行注释

//WS : ' ' -> skip;

WS   : [ \t\r\n]+ -> skip; // 空白， 后面的->skip表示antlr4在分析语言的文本时，符合这个规则的词法将被无视