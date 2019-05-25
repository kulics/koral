grammar Xs;

program: statement+;

statement: (annotationSupport)? CommentLine* 
exportStatement (CommentLine|NewLine)* namespaceSupportStatement*;

// 导出命名空间
exportStatement: '\\' nameSpace ArrowLeft blockLeft (importStatement|NewLine)* blockRight end;

// 导入命名空间
importStatement: (annotationSupport)? nameSpace (call NewLine? id)? end;

namespaceSupportStatement:
namespaceVariableStatement
|namespaceControlStatement
|namespaceFunctionStatement
|namespaceConstantStatement
|packageStatement
|protocolStatement
|enumStatement
|CommentLine
|NewLine
;

// 枚举
enumStatement: (annotationSupport)? id ArrowRight NewLine* type squareBracketLeft enumSupportStatement* squareBracketRight end;

enumSupportStatement: id (ArrowDouble (add)? integerExpr)? end;
// 命名空间变量
namespaceVariableStatement: (annotationSupport)? id (Define expression|Declared type (Assign expression)?) end;
// 命名空间控制
namespaceControlStatement: (annotationSupport)? id bracketLeft bracketRight (Define expression|Declared type (Assign expression)?) 
(blockLeft (packageControlSubStatement)+ blockRight)? end;
// 命名空间常量
namespaceConstantStatement: (annotationSupport)? id (Declared type)? ArrowDouble expression end;
// 命名空间函数
namespaceFunctionStatement: (annotationSupport)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) NewLine*
parameterClauseOut blockLeft (functionSupportStatement)* blockRight end;

// 定义包
packageStatement: (annotationSupport)? id (templateDefine)? ArrowRight blockLeft (packageSupportStatement)* blockRight 
 (packageNewStatement)* ('...' type packageOverrideStatement)? (protocolImplementStatement)* end;
// 包构造方法
packageNewStatement: (annotationSupport)? parameterClausePackage 
('...' bracketLeft expressionList? bracketRight)? blockLeft (functionSupportStatement)* blockRight;
// 入参
parameterClausePackage: bracketLeft parameter? (more parameter)* bracketRight;
// 包支持的语句
packageSupportStatement:
packageVariableStatement
|packageControlStatement
|packageFunctionStatement
|CommentLine
|NewLine
;
// 函数
packageFunctionStatement: (annotationSupport)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) NewLine*
parameterClauseOut blockLeft (functionSupportStatement)* blockRight end;
// 重写函数
packageOverrideFunctionStatement: (annotationSupport)? (n='_')? id parameterClauseIn t=(ArrowRight|FlowRight) NewLine*
parameterClauseOut blockLeft (functionSupportStatement)* blockRight end;
// 定义变量
packageVariableStatement: (annotationSupport)? id (Define expression|Declared type (Assign expression)?) end;
// 定义控制
packageControlStatement: (annotationSupport)? id bracketLeft bracketRight (Define expression|Declared type (Assign expression)?)
(blockLeft (packageControlSubStatement)+ blockRight)? end;
// 定义子方法
packageControlSubStatement: id blockLeft (functionSupportStatement)+ blockRight end;
// 包重载
packageOverrideStatement: blockLeft (packageOverrideFunctionStatement|CommentLine|NewLine)* BlockRight;
// 包扩展
packageExtensionStatement: (annotationSupport)? parameterClauseIn id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) NewLine*
parameterClauseOut blockLeft (packageFunctionStatement)* blockRight end;
// 协议
protocolStatement: (annotationSupport)? id (templateDefine)? ArrowLeft blockLeft (protocolSupportStatement)* blockRight end;
// 协议支持的语句
protocolSupportStatement:
protocolFunctionStatement
|protocolControlStatement
|CommentLine
|NewLine
;
// 定义控制
protocolControlStatement: (annotationSupport)? id bracketLeft bracketRight Declared type (protocolControlSubStatement)* end;
// 定义子方法
protocolControlSubStatement: id end?;
// 函数
protocolFunctionStatement: (annotationSupport)? id (templateDefine)? parameterClauseIn 
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
protocolImplementStatement: nameSpaceItem (templateCall)? blockLeft (protocolImplementSupportStatement)* blockRight;
// 控制实现
implementControlStatement: (annotationSupport)? expression bracketLeft bracketRight (Define expression|Declared type (Assign expression)?)
(blockLeft (packageControlSubStatement)+ blockRight)? end;
// 函数实现
implementFunctionStatement: (annotationSupport)? id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) NewLine*
parameterClauseOut blockLeft (functionSupportStatement)* blockRight end;
// 事件实现
implementEventStatement: id ':' 'Event<' nameSpaceItem '>' end;
// 函数
functionStatement: id (templateDefine)? parameterClauseIn t=(ArrowRight|FlowRight) NewLine* parameterClauseOut blockLeft
(functionSupportStatement)* blockRight end;
// 返回
returnStatement: ArrowLeft tuple end;
// 入参
parameterClauseIn: bracketLeft parameter? (more parameter)*  bracketRight ;
// 出参
parameterClauseOut: bracketLeft parameter? (more parameter)*  bracketRight ;
// 参数结构
parameter: (annotationSupport)? id ':' type ('=' expression)?;

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
| usingStatement
| checkStatement
| reportStatement
| functionStatement
| variableStatement
| variableDeclaredStatement
| assignStatement
| expressionStatement
| CommentLine
| NewLine
;

// 条件判断
judgeCaseStatement: expression Judge (caseStatement)+ end;
// 缺省条件声明
caseDefaultStatement: Discard blockLeft (functionSupportStatement)* blockRight;
// 条件声明
caseExprStatement: (expression| (id)? ':' type) blockLeft (functionSupportStatement)* blockRight;
// 判断条件声明
caseStatement: caseDefaultStatement|caseExprStatement;
// 判断
judgeStatement:
judgeIfStatement (judgeElseIfStatement)* judgeElseStatement end
| judgeIfStatement (judgeElseIfStatement)* end;
// else 判断
judgeElseStatement: Discard blockLeft (functionSupportStatement)* blockRight;
// if 判断
judgeIfStatement: Judge expression blockLeft (functionSupportStatement)* blockRight;
// else if 判断
judgeElseIfStatement: expression blockLeft (functionSupportStatement)* blockRight;
// 循环
loopStatement: iteratorStatement Loop id blockLeft (functionSupportStatement)* blockRight end;
// 集合循环
loopEachStatement: expression Loop ('[' id ']')? id blockLeft (functionSupportStatement)* blockRight end;
// 条件循环
loopCaseStatement: Loop expression blockLeft (functionSupportStatement)* blockRight end;
// 无限循环
loopInfiniteStatement: Loop blockLeft (functionSupportStatement)* blockRight end;
// 跳出循环
loopJumpStatement: ArrowLeft Loop end;
// 跳出当前循环
loopContinueStatement: ArrowRight Loop end;
// 检查
checkStatement: 
Check blockLeft (functionSupportStatement)* blockRight (checkErrorStatement)* checkFinallyStatment end
|Check blockLeft (functionSupportStatement)* blockRight (checkErrorStatement)+ end;
// 定义检查变量
usingStatement: expression Check expression (Declared type)? end;
// 错误处理
checkErrorStatement: (id|id Declared type) blockLeft (functionSupportStatement)* blockRight;
// 最终执行
checkFinallyStatment: Discard blockLeft (functionSupportStatement)* blockRight;

// 报告错误
reportStatement: Check bracketLeft (expression)? bracketRight end;
// 迭代器
iteratorStatement: '[' expression op=('<'|'<='|'>'|'>=') expression more expression ']' | '[' expression op=('<'|'<='|'>'|'>=') expression ']';

// 定义变量
variableStatement: expression (Define|Declared type Assign) expression end;
// 声明变量
variableDeclaredStatement: expression Declared type end;
// 赋值
assignStatement: expression assign expression end;

expressionStatement: expression end;

// 基础表达式
primaryExpression: 
id (templateCall)?
| t=Self
| t=Discard
| bracketLeft expression bracketRight
| dataStatement
;

// 表达式
expression:
linq // 联合查询
| callFunc // 函数调用
| primaryExpression
| callBase // 调用继承
| callSelf // 调用自己
| callNameSpace // 调用命名空间
| callElement //调用元素
| callNew // 构造类对象
| callPkg // 新建包
| getType // 获取类型
| callAwait // 异步等待调用
| list // 列表
| set // 集合
| dictionary // 字典
| lambda // lambda表达式
| functionExpression // 函数
| pkgAnonymous // 匿名包
| tupleExpression //元组表达式
| plusMinus // 正负处理
| negate // 取反
| expression call NewLine? callExpression // 链式调用
| expression judgeType type // 类型判断表达式
| expression judge expression // 判断型表达式
| expression add expression // 和型表达式
| expression mul expression // 积型表达式
| expression pow expression // 幂型表达式
| expression op=Judge // 可空判断
| expression typeConversion // 类型转换
| stringExpression // 字符串插值
;

callBase: '...' callExpression;
callSelf: '..' callExpression;
callNameSpace: ('\\' id)+ call NewLine? callExpression;

callExpression:
callElement // 访问元素
| callFunc // 函数调用
| callPkg //
| id // id
| callExpression call NewLine? callExpression // 链式调用
;

tuple: bracketLeft (expression (more expression)* )? bracketRight; // 元组

expressionList: expression (more expression)* ; // 表达式列

annotationSupport: annotation (NewLine|CommentLine)?;

annotation: '[' (id ArrowRight)? annotationList ']'; // 注解

annotationList: annotationItem (more annotationItem)*;

annotationItem: id ( bracketLeft annotationAssign (more annotationAssign)* bracketRight)? ;

annotationAssign: (id '=')? expression ;

callFunc: id (templateCall)? tuple; // 函数调用

callElement : id op=Judge? '[' (expression | slice) ']';

callPkg: type blockLeft (pkgAssign|listAssign|setAssign|dictionaryAssign)? blockRight; // 新建包

callNew: '<' type '>' bracketLeft NewLine? expressionList? NewLine? bracketRight; // 构造类对象

getType: Judge bracketLeft (expression|':' type) bracketRight;

typeConversion: Declared type; // 类型转化

pkgAssign: pkgAssignElement (more pkgAssignElement)* ; // 简化赋值

pkgAssignElement: name Assign expression; // 简化赋值元素

listAssign: expression (more expression)* ;

setAssign: '[' expression ']' (more '[' expression ']')* ;

dictionaryAssign: dictionaryElement (more dictionaryElement)* ;

callAwait: FlowLeft expression; // 异步调用

list: blockLeft expression (more expression)* blockRight; // 列表

set: blockLeft '[' expression ']' (more '[' expression ']')* blockRight; // 无序集合

dictionary:  blockLeft dictionaryElement (more dictionaryElement)* blockRight; // 字典

dictionaryElement: '[' expression ']' expression; // 字典元素

slice: sliceFull | sliceStart | sliceEnd;

sliceFull: expression op=('<'|'<='|'>'|'>=') expression; 
sliceStart: expression op=('<'|'<='|'>'|'>=');
sliceEnd: op=('<'|'<='|'>'|'>=') expression; 

nameSpace: id ('\\' id)*;

nameSpaceItem: (('\\' id)+ call NewLine?)? id;

name: id (call NewLine? id)* ;

templateDefine: '<' templateDefineItem (more templateDefineItem)* '>';

templateDefineItem: id (':' id)?; 

templateCall: '<' type (more type)* '>';

lambda: blockLeft (lambdaIn)? t=(ArrowRight|FlowRight) NewLine* expressionList blockRight
| blockLeft (lambdaIn)? t=(ArrowRight|FlowRight) NewLine* 
(functionSupportStatement)* blockRight;

lambdaIn: id (more id)*;

pkgAnonymous: pkgAnonymousAssign; // 匿名包

pkgAnonymousAssign: blockLeft (pkgAnonymousAssignElement (more pkgAnonymousAssignElement)* NewLine)+ blockRight; // 简化赋值

pkgAnonymousAssignElement: name '=' expression; // 简化赋值元素

functionExpression: anonymousParameterClauseIn t=(ArrowRight|FlowRight) NewLine*
parameterClauseOut blockLeft (functionSupportStatement)* blockRight;

// 入参
anonymousParameterClauseIn: bracketLeft parameter? (more parameter)*  bracketRight  ;

tupleExpression: bracketLeft expression (more expression)*  bracketRight; // 元组

plusMinus: add expression;

negate: wave expression;

linq: linqHeadKeyword NewLine? expression ArrowDouble NewLine?  (linqItem)+ k=('by'|'select') NewLine? expression;

linqItem: linqBodyKeyword (expression)? ArrowDouble NewLine?;

linqKeyword: linqHeadKeyword | linqBodyKeyword ;
linqHeadKeyword: k='from';
linqBodyKeyword: k=('where'|'select'|'group'|'into'|'orderby'|'join'|'let'|'in'|'on'|'equals'|'by'|'ascending'|'descending') ;

stringExpression: Text (stringExpressionElement)+;

stringExpressionElement: expression Text;

// 基础数据
dataStatement:
floatExpr
| integerExpr
| t=Text
| t=Char
| t=True
| t=False
| nil 
| t=Undefined
;

floatExpr: integerExpr call integerExpr;
integerExpr: Number+;

// 类型
typeNotNull:
typeTuple
| typeArray
| typeList
| typeSet
| typeDictionary
| typeBasic
| typePackage
| typeFunction
| typeAny
;

typeNullable: Judge typeNotNull;
type: typeNotNull | typeNullable;

typeTuple: bracketLeft type (more type)+ bracketRight;
typeArray: '[:]' type;
typeList: '[]' type;
typeSet: '[' type ']';
typeDictionary: '[' type ']' type;
typePackage: nameSpaceItem (templateCall)? ;
typeFunction: typeFunctionParameterClause t=(ArrowRight|FlowRight) NewLine* typeFunctionParameterClause;
typeAny: BlockLeft BlockRight;

// 函数类型参数
typeFunctionParameterClause: bracketLeft type? (more type)*  bracketRight;

// 基础类型名
typeBasic:
t=TypeI8
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
| t=TypeInt
| t=TypeNum
;
// nil值
nil: bracketLeft bracketRight;
// bool值
bool: t=True|t=False;

judgeType: op=('=='|'><') Declared;
judge: op=('|' | '&' | '==' | '><' | '<' | '>' | '<=' | '>=');
assign: op=(Assign | '+=' | '-=' | '*=' | '/=' | '%=');
add: op=('+' | '-');
mul: op=('*' | '/' | '%');
pow: op=('**' | '//' | '%%');
call: op='.' NewLine* CommentLine*;
wave: op='~';

id: (idItem)+;

idItem: op=(IDPublic|IDPrivate)
|typeBasic
|linqKeyword;

end: Terminate | NewLine | CommentLine;
Terminate: ';';

more: ',' CommentLine* NewLine* ;

blockLeft: BlockLeft CommentLine* NewLine*;
BlockLeft: '{';
blockRight: CommentLine* NewLine* BlockRight;
BlockRight: '}';

bracketLeft: '(';
bracketRight: ')';

squareBracketLeft: '[' CommentLine* NewLine*;
squareBracketRight: CommentLine* NewLine* ']';

Define: ':=';
Declared: ':';
Assign: '=';

Self: '..';

ArrowRight: '->';
ArrowLeft: '<-';

FlowRight: '~>';
FlowLeft: '<~';

ArrowDouble: '=>';

Judge: '?';

Loop: '@';

Check: '!';

TypeI8: 'I8';
TypeU8: 'U8';
TypeI16: 'I16';
TypeU16: 'U16';
TypeI32: 'I32';
TypeU32: 'U32';
TypeI64: 'I64';
TypeU64: 'U64';
TypeF32: 'F32';
TypeF64: 'F64';
TypeChr: 'Chr';
TypeStr: 'Str';
TypeBool: 'Bool';
TypeInt: 'Int';
TypeNum: 'Num';
True: 'True';
False: 'False';
Undefined: 'Undefined';

Number: DIGIT+ ; // 整数
fragment DIGIT: [0-9] ;             // 单个数字
Text: '"' (~[\\\r\n])*? '"'; // 文本
Char: '\'' (~[\\\r\n])*? '\''; // 单字符
IDPrivate: '_' [a-zA-Z0-9_]+; // 私有标识符
IDPublic: [a-zA-Z] [a-zA-Z0-9_]*; // 公有标识符
Discard: '_'; // 匿名变量

Comment: '##' .*? '##' -> skip; // 结构注释
CommentLine: '#' .*? NewLine; // 行注释

NewLine: '\n'; 
//WS: (' ' |'\t' |'\n' |'\r' )+ -> skip ;

WS: [ \t]+ -> skip; // 空白， 后面的->skip表示antlr4在分析语言的文本时，符合这个规则的词法将被无视