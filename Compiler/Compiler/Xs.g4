grammar Xs;

program: statement+;

statement: (annotationSupport)? CommentLine* 
exportStatement CommentLine* NewLine* namespaceSupportStatement*;

// 导出命名空间
exportStatement: '\\' nameSpace blockLeft (importStatement|NewLine)* BlockRight end;

// 导入命名空间
importStatement: (annotationSupport)? nameSpace (call NewLine? id)? end;

namespaceSupportStatement:
packageStaticStatement
|packageStatement
|packageExtensionStatement
|protocolStatement
|enumStatement
|CommentLine
|NewLine
;

// 枚举
enumStatement: (annotationSupport)? id ArrowRight NewLine* Judge blockLeft enumSupportStatement* BlockRight;

enumSupportStatement: id ('=' (add)? Integer)? end;
// 静态包
packageStaticStatement:(annotationSupport)? id (templateDefine)? (packageInitStatement)? 
ArrowRight NewLine* blockLeft (packageStaticSupportStatement)* BlockRight;
// 静态包支持的语句
packageStaticSupportStatement:
namespaceVariableStatement
|namespaceFunctionStatement
|namespaceConstantStatement
|CommentLine
|NewLine
;
// 命名空间变量
namespaceVariableStatement:(annotationSupport)? expression (Define expression|Declared type (Assign expression)?) 
(blockLeft (packageControlSubStatement)+ BlockRight)? end;
// 命名空间常量
namespaceConstantStatement: (annotationSupport)? id (Declared type)? expression end;
// 命名空间函数
namespaceFunctionStatement:(annotationSupport)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) NewLine*
parameterClauseOut blockLeft (functionSupportStatement)* BlockRight end;

// 定义包
packageStatement:(annotationSupport)? id (templateDefine)? parameterClausePackage (packageInitStatement)? 
 ArrowRight blockLeft (packageSupportStatement)* BlockRight 
 (extend packageOverrideStatement)? (protocolImplementStatement)* ;
// 继承
extend: ':' type blockLeft expressionList? BlockRight;
// 入参
parameterClausePackage : blockLeft parameter? (more parameter)*  BlockRight  ;
// 包支持的语句
packageSupportStatement:
packageVariableStatement
|packageFunctionStatement
|CommentLine
|NewLine
;
// 包构造方法
packageInitStatement:(annotationSupport)? '..' blockLeft (functionSupportStatement)* BlockRight;
// 函数
packageFunctionStatement:(annotationSupport)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) NewLine*
parameterClauseOut blockLeft (functionSupportStatement)* BlockRight end;
// 重写函数
packageOverrideFunctionStatement:(annotationSupport)? (n=':')? id parameterClauseIn t=(ArrowRight|FlowRight) NewLine*
parameterClauseOut blockLeft (functionSupportStatement)* BlockRight end;
// 定义变量
packageVariableStatement:(annotationSupport)? expression (Define expression|Declared type (Assign expression)?)
(blockLeft (packageControlSubStatement )+ BlockRight)? end;
// 定义子方法
packageControlSubStatement: id (blockLeft (functionSupportStatement)+ BlockRight)? end;
// 包重载
packageOverrideStatement: blockLeft (packageOverrideFunctionStatement)* BlockRight;
// 包扩展
packageExtensionStatement: id (templateDefine)? ArrowLeft blockLeft (packageExtensionSupportStatement)* BlockRight;
// 包扩展支持的语句
packageExtensionSupportStatement: 
packageFunctionStatement
|CommentLine
|NewLine
;
// 协议
protocolStatement:(annotationSupport)? id (templateDefine)? '::' blockLeft (protocolSupportStatement)* BlockRight;
// 协议支持的语句
protocolSupportStatement:
protocolFunctionStatement
|protocolControlStatement
|CommentLine
|NewLine
;
// 定义控制
protocolControlStatement:(annotationSupport)? id Declared type (blockLeft (protocolControlSubStatement)* BlockRight)? end;
// 定义子方法
protocolControlSubStatement: id end?;
// 函数
protocolFunctionStatement:(annotationSupport)? id (templateDefine)? parameterClauseIn 
t=(ArrowRight|FlowRight) NewLine* parameterClauseOut end;
// 协议实现支持的语句
protocolImplementSupportStatement:
implementFunctionStatement
|implementControlStatement
|implementEventStatement
|CommentLine
|NewLine
;
// 实现协议
protocolImplementStatement: ':' nameSpaceItem (templateCall)? blockLeft (protocolImplementSupportStatement)* BlockRight;
// 控制实现
implementControlStatement:(annotationSupport)? expression (Define expression|Declared type (Assign expression)?)
(blockLeft (packageControlSubStatement)+ BlockRight)? end;
// 函数实现
implementFunctionStatement:(annotationSupport)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) NewLine*
parameterClauseOut blockLeft (functionSupportStatement)* BlockRight end;
// 事件实现
implementEventStatement: id ':' nameSpaceItem '!!' end;
// 函数
functionStatement:id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) NewLine* parameterClauseOut blockLeft
(functionSupportStatement)* BlockRight end;
// 返回
returnStatement: ArrowLeft tuple end;
// 入参
parameterClauseIn : '(' parameter? (more parameter)*  ')'  ;
// 出参
parameterClauseOut : '(' parameter? (more parameter)*  ')'  ;
// 参数结构
parameter :(annotationSupport)? id ':' type ('=' expression)?;

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
| CommentLine
| NewLine
;

// 条件判断
judgeCaseStatement: Judge expression ArrowRight (caseStatement)+ end;
// 缺省条件声明
caseDefaultStatement: Discard blockLeft (functionSupportStatement)* BlockRight;
// 条件声明
caseExprStatement: (expression| (id)? ':' type) blockLeft (functionSupportStatement)* BlockRight;
// 判断条件声明
caseStatement: caseDefaultStatement|caseExprStatement;
// 判断
judgeStatement:
judgeIfStatement (judgeElseIfStatement)* judgeElseStatement end
| judgeIfStatement (judgeElseIfStatement)* end;
// else 判断
judgeElseStatement:Discard blockLeft (functionSupportStatement)* BlockRight;
// if 判断
judgeIfStatement:Judge expression blockLeft (functionSupportStatement)* BlockRight;
// else if 判断
judgeElseIfStatement: expression blockLeft (functionSupportStatement)* BlockRight;
// 循环
loopStatement:Loop id ArrowLeft iteratorStatement blockLeft (functionSupportStatement)* BlockRight end;
// 集合循环
loopEachStatement:Loop ('[' id ']')? id ArrowLeft expression blockLeft (functionSupportStatement)* BlockRight end;
// 条件循环
loopCaseStatement:Loop Judge expression blockLeft (functionSupportStatement)* BlockRight end;
// 无限循环
loopInfiniteStatement:Loop blockLeft (functionSupportStatement)* BlockRight end;
// 跳出循环
loopJumpStatement:ArrowLeft Loop end;
// 跳出当前循环
loopContinueStatement:ArrowRight Loop end;
// 检查
checkStatement: 
Check usingExpression blockLeft (functionSupportStatement)* BlockRight end
|Check (usingExpression)? blockLeft (functionSupportStatement)* BlockRight (checkErrorStatement)* checkFinallyStatment end
|Check (usingExpression)? blockLeft (functionSupportStatement)* BlockRight (checkErrorStatement)+ end;
// 定义变量
usingExpression: expression (Define|Declared type Assign) expression;
// 错误处理
checkErrorStatement:(id|id Declared type) blockLeft (functionSupportStatement)* BlockRight;
// 最终执行
checkFinallyStatment: Discard blockLeft (functionSupportStatement)* BlockRight;

// 报告错误
reportStatement: Check '(' (expression)? ')' end;
// 迭代器
iteratorStatement: '[' expression op=('<'|'<='|'>'|'>=') expression more expression ']' | '[' expression op=('<'|'<='|'>'|'>=') expression ']';

// 定义变量
variableStatement: expression (Define|Declared type Assign) expression end;
// 声明变量
variableDeclaredStatement: expression Declared type end;
// 赋值
assignStatement: expression assign expression end;

execFuncStatement: FlowLeft? (expression call|('\\' id)+ call)? callFunc end;

// 基础表达式
primaryExpression: 
id (templateCall)?
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
| tupleExpression //元组表达式
| plusMinus // 正负处理
| negate // 取反
| expression call NewLine? callExpression // 链式调用
| expression judge expression // 判断型表达式
| expression add expression // 和型表达式
| expression mul expression // 积型表达式
| expression op=(Judge|Check) // 可空判断
;

callSelf: '..' callExpression;
callNameSpace: ('\\' id)+ call NewLine? callExpression;

callExpression:
callElement // 访问元素
| callFunc // 函数调用
| callPkg //
| id // id
| callExpression call NewLine? callExpression // 链式调用
;

tuple : '(' (expression (more expression)* )? ')'; // 元组

expressionList : expression (more expression)* ; // 表达式列

annotationSupport: annotation (NewLine|CommentLine)?;

annotation: '`' (id ArrowRight)? annotationList '`'; // 注解

annotationList: annotationItem (more annotationItem)*;

annotationItem: id ( '{' annotationAssign (more annotationAssign)* '}')? ;

annotationAssign: (id '=')? expression ;

callFunc: id (templateCall)? tuple; // 函数调用

callElement : id op=(Judge|Check)? '[' (expression | slice) ']';

callPkg: type '{' expressionList? ( ArrowLeft NewLine? (pkgAssign|listAssign|dictionaryAssign))? NewLine? '}'; // 新建包

getType: Judge '(' (expression|':' type) ')';

pkgAssign: (pkgAssignElement (more pkgAssignElement)*)? ; // 简化赋值

pkgAssignElement: name Assign expression; // 简化赋值元素

listAssign: (expression (more expression)*)? ;

dictionaryAssign: (dictionaryElement (more dictionaryElement)*)? ;

callAwait: FlowLeft expression; // 异步调用

array : '{|' (expression (more expression)*)? '|}'; // 数组

list : '{' (expression (more expression)*)? '}'; // 列表

dictionary :  '{' (dictionaryElement (more dictionaryElement)*)? '}'; // 字典

dictionaryElement: '[' expression ']' expression; // 字典元素

slice: sliceFull | sliceStart | sliceEnd;

sliceFull: expression op=('<'|'<='|'>'|'>=') expression; 
sliceStart: expression op=('<'|'<='|'>'|'>=');
sliceEnd: op=('<'|'<='|'>'|'>=') expression; 

nameSpace: id ('\\' id)*;

nameSpaceItem: (('\\' id)+ call NewLine?)? id;

name: id (call NewLine? id)* ;

templateDefine: '<' id (more id)* '>';

templateCall: '<' type (more type)* '>';

lambda : blockLeft (lambdaIn)? t=(ArrowRight|FlowRight) NewLine* expressionList BlockRight
| blockLeft (lambdaIn)? t=(ArrowRight|FlowRight) NewLine* 
(functionSupportStatement)* BlockRight;

lambdaIn : id (more id)*;

pkgAnonymous: pkgAnonymousAssign; // 匿名包

pkgAnonymousAssign: blockLeft (pkgAnonymousAssignElement NewLine)+ BlockRight; // 简化赋值

pkgAnonymousAssignElement: name ':=' expression Terminate?; // 简化赋值元素

function : anonymousParameterClauseIn t=(ArrowRight|FlowRight) NewLine*
parameterClauseOut blockLeft (functionSupportStatement)* BlockRight;

// 入参
anonymousParameterClauseIn : '(' parameter? (more parameter)*  ')'  ;

tupleExpression : '(' expression (more expression)*  ')'; // 元组

plusMinus : add expression;

negate : wave expression;

linq: linqHeadKeyword expression (linqItem)+ k=('by'|'select') expression;

linqItem: linqBodyKeyword | expression ;

linqKeyword: linqHeadKeyword | linqBodyKeyword | NewLine;
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

typeTuple : '(' type (more type)+ ')';
typeList : '[' type ']';
typeArray : '[' '|' type '|' ']';
typeDictionary :  '[' '[' type ']' type ']';
typePackage : nameSpaceItem (templateCall)? ;
typeFunction : typeFunctionParameterClause ArrowRight NewLine* typeFunctionParameterClause;

// 函数类型参数
typeFunctionParameterClause : '(' type? (more type)*  ')';

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

end: Terminate | NewLine | CommentLine;
Terminate : ';';

more : ',' CommentLine* NewLine* ;

blockLeft : BlockLeft NewLine*;
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

Comment : '##' .*? '##' -> skip; // 结构注释
CommentLine : '#' .*? NewLine; // 行注释

NewLine: '\n'; 
//WS : (' ' |'\t' |'\n' |'\r' )+ -> skip ;

WS   : [ \t]+ -> skip; // 空白， 后面的->skip表示antlr4在分析语言的文本时，符合这个规则的词法将被无视