grammar Xs;

program: statement+;

statement: (annotationSupport)? exportStatement namespaceSupportStatement*;

// 导出命名空间
exportStatement: '\\' nameSpace BlockLeft (importStatement)* BlockRight Terminate?;

// 导入命名空间
importStatement: (annotationSupport)? nameSpace (call id)? Terminate?;

namespaceSupportStatement:
packageStaticStatement
|packageStatement
|packageExtensionStatement
|protocolStatement
|enumStatement
;

// 枚举
enumStatement: (annotationSupport)? id call ArrowRight Judge BlockLeft enumSupportStatement* BlockRight Terminate?;

enumSupportStatement: id ('=' (add)? Integer)?;
// 静态包
packageStaticStatement:(annotationSupport)? id (templateDefine)? call (packageInitStatement)? ArrowRight BlockLeft (packageStaticSupportStatement)* BlockRight;
// 静态包支持的语句
packageStaticSupportStatement:
namespaceVariableStatement
|namespaceControlSubStatement
|namespaceFunctionStatement
|namespaceConstantStatement
;
// 命名空间变量
namespaceVariableStatement:(annotationSupport)? expression (Define expression|Declared type (Assign expression)?) (BlockLeft (namespaceControlSubStatement )* BlockRight)? Terminate?;
// 命名空间常量
namespaceConstantStatement: (annotationSupport)? id (Declared type)? expression Terminate?;
// 定义子方法
namespaceControlSubStatement: id BlockLeft (functionSupportStatement)* BlockRight;
// 命名空间函数
namespaceFunctionStatement:(annotationSupport)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight;

// 定义包
packageStatement:(annotationSupport)? id (templateDefine)? parameterClausePackage (extend)? (packageInitStatement)? 
 ArrowRight BlockLeft (packageSupportStatement)* BlockRight (packageOverrideStatement)? protocolImplementStatement* Terminate?;
// 继承
extend: '::' type '{' expressionList? '}';
// 入参
parameterClausePackage : '{' parameter? (',' parameter)*  '}'  ;
// 包支持的语句
packageSupportStatement:
packageVariableStatement
|packageFunctionStatement
;
// 包构造方法
packageInitStatement:(annotationSupport)? BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 函数
packageFunctionStatement:(annotationSupport)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 重写函数
packageOverrideFunctionStatement:(annotationSupport)? id parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 定义变量
packageVariableStatement:(annotationSupport)? expression (Define expression|Declared type (Assign expression)?) (BlockLeft (packageControlSubStatement )* BlockRight)? Terminate?;
// 定义子方法
packageControlSubStatement: id BlockLeft (functionSupportStatement)* BlockRight;
// 包重载
packageOverrideStatement: '::' nameSpaceItem (templateCall)? BlockLeft (packageOverrideFunctionStatement)* BlockRight;
// 包扩展
packageExtensionStatement: id (templateDefine)? ArrowLeft BlockLeft (packageExtensionSupportStatement)* BlockRight Terminate?;
// 包扩展支持的语句
packageExtensionSupportStatement: 
packageFunctionStatement
;
// 协议
protocolStatement:(annotationSupport)? id (templateDefine)? ArrowRight BlockLeft (protocolSupportStatement )* BlockRight Terminate?;
// 协议支持的语句
protocolSupportStatement:
protocolFunctionStatement
|protocolControlStatement
;
// 定义控制
protocolControlStatement:(annotationSupport)? id Declared type (BlockLeft (protocolControlSubStatement )* BlockRight)? Terminate?;
// 定义子方法
protocolControlSubStatement: id BlockLeft BlockRight;
// 函数
protocolFunctionStatement:(annotationSupport)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 协议实现支持的语句
protocolImplementSupportStatement:
implementFunctionStatement
|implementControlStatement
|implementEventStatement
;
// 实现协议
protocolImplementStatement: ':' nameSpaceItem (templateCall)? BlockLeft (protocolImplementSupportStatement)* BlockRight;
// 控制实现
implementControlStatement:(annotationSupport)? expression (Define expression|Declared type (Assign expression)?) (BlockLeft (packageControlSubStatement)* BlockRight)? Terminate?;
// 函数实现
implementFunctionStatement:(annotationSupport)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight Terminate?;
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
parameter :(annotationSupport)? id ':' type;

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
loopStatement:Loop (id ArrowLeft)? iteratorStatement BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 集合循环
loopEachStatement:Loop ((id ArrowRight)? id ArrowLeft)?  expression BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 条件循环
loopCaseStatement:Loop Judge expression BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 无限循环
loopInfiniteStatement:Loop BlockLeft (functionSupportStatement)* BlockRight Terminate?;
// 跳出循环
loopJumpStatement:ArrowLeft Loop Terminate?;
// 跳出当前循环
loopContinueStatement:ArrowRight Loop Terminate?;
// 检查
checkStatement: 
Check usingExpression BlockLeft (functionSupportStatement)* BlockRight Terminate?
|Check (usingExpression)? BlockLeft (functionSupportStatement)* BlockRight (ArrowRight (checkErrorStatement)+)? checkFinallyStatment Terminate?
|Check (usingExpression)? BlockLeft (functionSupportStatement)* BlockRight ArrowRight (checkErrorStatement)+ Terminate?;
// 定义变量
usingExpression: expression (Define|Declared type Assign) expression;
// 错误处理
checkErrorStatement:(Declared type|id Declared type)? BlockLeft (functionSupportStatement)* BlockRight;
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

execFuncStatement: FlowLeft? (expression call|('\\' id)+ call)? callFunc Terminate?;

// 基础表达式
primaryExpression: 
id (templateCall)?
| t=Self
| t=Discard
| dataStatement
| '_(' expression ')'
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
| tupleExpression //元组表达式
| plusMinus // 正负处理
| negate // 取反
| expression call callExpression // 链式调用
| expression judge expression // 判断型表达式
| expression add expression // 和型表达式
| expression mul expression // 积型表达式
| expression op=(Judge|Check) // 可空判断
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

expressionList : expression (',' expression)* ; // 表达式列

annotationSupport: annotation ;

annotation: '`' (id ':')? annotationList '`' ; // 注解

annotationList: annotationItem (',' annotationItem)*;

annotationItem: id ( '{' annotationAssign (',' annotationAssign)* '}')? ;

annotationAssign: (id '=')? expression ;

callFunc: id (templateCall)? tuple; // 函数调用

callElement : id op=(Judge|Check)? '[' (expression | slice) ']';

callPkg: type '{' expressionList? ( ArrowLeft (pkgAssign|listAssign|dictionaryAssign))? '}'; // 新建包

getType: Judge '(' (expression|':' type) ')';

pkgAssign: (pkgAssignElement (',' pkgAssignElement)*)? ; // 简化赋值

pkgAssignElement: name Assign expression; // 简化赋值元素

listAssign: (expression (',' expression)*)? ;

dictionaryAssign: (dictionaryElement (',' dictionaryElement)*)? ;

callAwait: FlowLeft expression; // 异步调用

array : '_{|' (expression (',' expression)*)? '|}'; // 数组

list : '_{' (expression (',' expression)*)? '}'; // 列表

dictionary :  '_{' (dictionaryElement (',' dictionaryElement)*)? '}'; // 字典

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
| '$' (lambdaIn)? t=(ArrowRight|FlowRight) BlockLeft (functionSupportStatement)* BlockRight
| lambdaShort;

lambdaIn : id (',' id)*;

lambdaShort : '$' expressionList;

pkgAnonymous: pkgAnonymousAssign; // 匿名包

pkgAnonymousAssign: '_{' (pkgAnonymousAssignElement)+ BlockRight; // 简化赋值

pkgAnonymousAssignElement: name ':=' expression Terminate?; // 简化赋值元素

function : anonymousParameterClauseIn t=(ArrowRight|FlowRight) parameterClauseOut BlockLeft (functionSupportStatement)* BlockRight;

// 入参
anonymousParameterClauseIn : '_(' parameter? (',' parameter)*  ')'  ;

tupleExpression : '_(' expression (',' expression)*  ')'; // 元组

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

typeNullable : typeNotNull (Judge|Check);
type : typeNotNull | typeNullable;

typeTuple : '(' type (',' type)+ ')';
typeList : '[' type ']';
typeArray : '[' '|' type '|' ']';
typeDictionary :  '[' type ArrowRight type ']';
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
Null : 'nil';

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

//NEWLINE: '\r'? '\n'; 
//WS : (' ' |'\t' |'\n' |'\r' )+ -> skip ;

WS   : [ \t\r\n]+ -> skip; // 空白， 后面的->skip表示antlr4在分析语言的文本时，符合这个规则的词法将被无视