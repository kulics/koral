parser grammar XsParser;

options { tokenVocab=XsLexer; }

program: statement+;

statement: (New_Line)* (annotationSupport)?  
exportStatement (New_Line)* namespaceSupportStatement*;

// 导出命名空间
exportStatement: TextLiteral left_brace (importStatement|New_Line)* right_brace end;

// 导入命名空间
importStatement: (annotationSupport)? TextLiteral (id call?)? end;

namespaceSupportStatement:
namespaceVariableStatement
|namespaceControlStatement
|namespaceFunctionStatement
|namespaceConstantStatement
|packageStatement
|protocolStatement
|packageFunctionStatement
|packageNewStatement
|enumStatement
|typeAliasStatement
|typeRedefineStatement
|New_Line
;

// 类型别名
typeAliasStatement: id Equal_Arrow typeType end;
// 类型重定义
typeRedefineStatement: id Right_Arrow typeType end;

// 枚举
enumStatement: (annotationSupport)? id Right_Arrow New_Line* typeType left_brack enumSupportStatement* right_brack end;

enumSupportStatement: id (Equal (add)? integerExpr)? end;
// 命名空间变量
namespaceVariableStatement: (annotationSupport)? id (Colon_Equal expression|Colon typeType (Equal expression)?) end;
// 命名空间控制
namespaceControlStatement: (annotationSupport)? id left_paren right_paren (Colon_Equal expression|Colon typeType (Equal expression)?) 
(Right_Arrow (packageControlSubStatement)+)? end;
// 命名空间常量
namespaceConstantStatement: (annotationSupport)? id (Colon typeType Colon|Colon_Colon) expression end;
// 命名空间函数
namespaceFunctionStatement: (annotationSupport)? id (templateDefine)? parameterClauseIn t=(Right_Arrow|Right_Flow) New_Line*
parameterClauseOut left_brace (functionSupportStatement)* right_brace end;

// 定义包
packageStatement: (annotationSupport)? id (templateDefine)? Right_Arrow left_brace (packageSupportStatement)* right_brace end;

// 包支持的语句
packageSupportStatement:
includeStatement
|packageVariableStatement
|packageControlStatement
|packageEventStatement
|New_Line
;

// 包含
includeStatement: Colon typeType end;
// 包构造方法
packageNewStatement: (annotationSupport)? parameterClauseSelf Less Greater parameterClauseIn 
(left_paren expressionList? right_paren)? left_brace (functionSupportStatement)* right_brace;
// 函数
packageFunctionStatement: (annotationSupport)? parameterClauseSelf (n='_')? id (templateDefine)? parameterClauseIn t=(Right_Arrow|Right_Flow) New_Line*
parameterClauseOut left_brace (functionSupportStatement)* right_brace end;
// 定义变量
packageVariableStatement: (annotationSupport)? id (Colon_Equal expression|Colon typeType (Equal expression)?) end;
// 定义控制
packageControlStatement: (annotationSupport)? id left_paren right_paren (Colon_Equal expression|Colon typeType (Equal expression)?)
(Right_Arrow (packageControlSubStatement)+ )? end;
// 定义子方法
packageControlSubStatement: id left_brace (functionSupportStatement)+ right_brace;
// 定义包事件
packageEventStatement: id Colon left_brack Question right_brack nameSpaceItem end;
// 协议
protocolStatement: (annotationSupport)? id (templateDefine)? Left_Arrow left_brace (protocolSupportStatement)* right_brace end;
// 协议支持的语句
protocolSupportStatement:
includeStatement
|protocolFunctionStatement
|protocolControlStatement
|New_Line
;
// 定义控制
protocolControlStatement: (annotationSupport)? id left_paren right_paren Colon typeType
 (Right_Arrow protocolControlSubStatement (Comma protocolControlSubStatement)*)? end;
// 定义子方法
protocolControlSubStatement: id;
// 函数
protocolFunctionStatement: (annotationSupport)? id (templateDefine)? parameterClauseIn 
t=(Right_Arrow|Right_Flow) New_Line* parameterClauseOut end;

// 函数
functionStatement: id (templateDefine)? parameterClauseIn t=(Right_Arrow|Right_Flow) New_Line* parameterClauseOut left_brace
(functionSupportStatement)* right_brace end;
// 返回
returnStatement: Left_Arrow tuple end;
// 入参
parameterClauseIn: left_paren parameter? (more parameter)*  right_paren ;
// 出参
parameterClauseOut: left_paren parameter? (more parameter)*  right_paren ;
// 接收器
parameterClauseSelf: left_paren id Colon typeType right_paren (left_paren id right_paren)?;
// 参数结构
parameter: (annotationSupport)? id Colon typeType (Equal expression)?;

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
| channelAssignStatement
| assignStatement
| expressionStatement
| New_Line
;

// 条件判断
judgeCaseStatement: expression Question (caseStatement)+ end;
// 缺省条件声明
caseDefaultStatement: Discard left_brace (functionSupportStatement)* right_brace;
// 条件声明
caseExprStatement: (expression| (id)? Colon typeType) left_brace (functionSupportStatement)* right_brace;
// 判断条件声明
caseStatement: caseDefaultStatement|caseExprStatement;
// 判断
judgeStatement:
judgeIfStatement (judgeElseIfStatement)* judgeElseStatement end
| judgeIfStatement (judgeElseIfStatement)* end;
// else 判断
judgeElseStatement: Discard left_brace (functionSupportStatement)* right_brace;
// if 判断
judgeIfStatement: Question expression left_brace (functionSupportStatement)* right_brace;
// else if 判断
judgeElseIfStatement: expression left_brace (functionSupportStatement)* right_brace;
// 循环
loopStatement: iteratorStatement At id left_brace (functionSupportStatement)* right_brace end;
// 集合循环
loopEachStatement: expression At (Left_Brack id Right_Brack)? id left_brace (functionSupportStatement)* right_brace end;
// 条件循环
loopCaseStatement: At expression left_brace (functionSupportStatement)* right_brace end;
// 无限循环
loopInfiniteStatement: At left_brace (functionSupportStatement)* right_brace end;
// 跳出循环
loopJumpStatement: Left_Arrow At end;
// 跳出当前循环
loopContinueStatement: Right_Arrow At end;
// 检查
checkStatement: 
Bang left_brace (functionSupportStatement)* right_brace (checkErrorStatement)* checkFinallyStatment end
|Bang left_brace (functionSupportStatement)* right_brace (checkErrorStatement)+ end;
// 定义检查变量
usingStatement: expression Bang expression (Colon typeType)? end;
// 错误处理
checkErrorStatement: (id|id Colon typeType) left_brace (functionSupportStatement)* right_brace;
// 最终执行
checkFinallyStatment: Discard left_brace (functionSupportStatement)* right_brace;

// 报告错误
reportStatement: Bang left_paren (expression)? right_paren end;
// 迭代器
iteratorStatement: Left_Brack expression op=(Less|Less_Equal|Greater|Greater_Equal) expression
 more expression Right_Brack | Left_Brack expression op=(Less|Less_Equal|Greater|Greater_Equal) expression Right_Brack;

// 定义变量
variableStatement: expression (Colon_Equal|Colon typeType Equal) expression end;
// 声明变量
variableDeclaredStatement: expression Colon typeType end;
// 通道赋值
channelAssignStatement: expression Left_Brack Left_Arrow Right_Brack assign expression end;
// 赋值
assignStatement: expression assign expression end;

expressionStatement: expression end;

// 基础表达式
primaryExpression: 
id (templateCall)?
| t=Discard
| left_paren expression right_paren
| dataStatement
;

// 表达式
expression:
linq // 联合查询
| callFunc // 函数调用
| primaryExpression
| callChannel //调用通道
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
| expression op=Bang // 引用判断
| expression op=Question // 可空判断
| expression op=Left_Flow // 异步执行
| expression typeConversion // 类型转换
| expression call callExpression // 链式调用
| expression judgeType typeType // 类型判断表达式
| expression judge expression // 判断型表达式
| expression add expression // 和型表达式
| expression mul expression // 积型表达式
| expression pow expression // 幂型表达式
| stringExpression // 字符串插值
;

callExpression:
callElement // 访问元素
| callFunc // 函数调用
| callPkg //
| id // id
| callExpression call New_Line? callExpression // 链式调用
;

tuple: left_paren (expression (more expression)* )? right_paren; // 元组

expressionList: expression (more expression)* ; // 表达式列

annotationSupport: annotation (New_Line)?;

annotation: Left_Brack (id Right_Arrow)? annotationList Right_Brack; // 注解

annotationList: annotationItem (more annotationItem)*;

annotationItem: id ( left_paren annotationAssign (more annotationAssign)* right_paren)? ;

annotationAssign: (id Equal)? expression ;

callFunc: id (templateCall)? (tuple|lambda); // 函数调用

callChannel: id op=Question? Left_Brack Left_Arrow Right_Brack;

callElement: id op=Question? Left_Brack (slice | expression) Right_Brack;

callPkg: typeType left_brace (pkgAssign|listAssign|setAssign|dictionaryAssign)? right_brace; // 新建包

callNew: Less typeType Greater left_paren New_Line? expressionList? New_Line? right_paren; // 构造类对象

getType: Question left_paren (expression|Colon typeType) right_paren;

typeConversion: Colon left_paren typeType right_paren; // 类型转化

pkgAssign: pkgAssignElement (more pkgAssignElement)* ; // 简化赋值

pkgAssignElement: name Equal expression; // 简化赋值元素

listAssign: expression (more expression)* ;

setAssign: Left_Brack expression Right_Brack (more Left_Brack expression Right_Brack)* ;

dictionaryAssign: dictionaryElement (more dictionaryElement)* ;

callAwait: Left_Flow expression; // 异步调用

list: left_brace expression (more expression)* right_brace; // 列表

set: left_brace Left_Brack expression Right_Brack (more Left_Brack expression Right_Brack)* right_brace; // 无序集合

dictionary:  left_brace dictionaryElement (more dictionaryElement)* right_brace; // 字典

dictionaryElement: Left_Brack expression Right_Brack expression; // 字典元素

slice: sliceFull | sliceStart | sliceEnd;

sliceFull: expression op=(Less|Less_Equal|Greater|Greater_Equal) expression; 
sliceStart: expression op=(Less|Less_Equal|Greater|Greater_Equal);
sliceEnd: op=(Less|Less_Equal|Greater|Greater_Equal) expression; 

nameSpaceItem: (id call New_Line?)* id;

name: id (call New_Line? id)* ;

templateDefine: Less templateDefineItem (more templateDefineItem)* Greater;

templateDefineItem: id (Colon id)?; 

templateCall: Less typeType (more typeType)* Greater;

lambda: left_brace (lambdaIn)? t=(Right_Arrow|Right_Flow) New_Line* expressionList right_brace
| left_brace (lambdaIn)? t=(Right_Arrow|Right_Flow) New_Line* 
(functionSupportStatement)* right_brace;

lambdaIn: id (more id)*;

pkgAnonymous: pkgAnonymousAssign; // 匿名包

pkgAnonymousAssign: left_brace pkgAnonymousAssignElement (more pkgAnonymousAssignElement)* right_brace; // 简化赋值

pkgAnonymousAssignElement: name Equal expression; // 简化赋值元素

functionExpression: parameterClauseIn t=(Right_Arrow|Right_Flow) New_Line*
parameterClauseOut left_brace (functionSupportStatement)* right_brace;

tupleExpression: left_paren expression (more expression)*  right_paren; // 元组

plusMinus: add expression;

negate: wave expression;

linq: linqHeadKeyword New_Line? expression Right_Arrow New_Line?  (linqItem)+ k=(LinqSelect|LinqBy) New_Line? expression;

linqItem: linqKeyword (expression)? Right_Arrow New_Line?;

linqKeyword: linqHeadKeyword | linqBodyKeyword ;
linqHeadKeyword: k=LinqFrom;
linqBodyKeyword: k=(LinqSelect|LinqBy|LinqWhere|LinqGroup|LinqInto|LinqOrderby|LinqJoin|LinqLet|LinqIn|LinqOn|LinqEquals|LinqAscending|LinqDescending);

stringExpression: TextLiteral (stringExpressionElement)+;

stringExpressionElement: expression TextLiteral;

// 基础数据
dataStatement:
floatExpr
| integerExpr
| t=TextLiteral
| t=CharLiteral
| t=TrueLiteral
| t=FalseLiteral
| nilExpr
| t=UndefinedLiteral
;

floatExpr: integerExpr call integerExpr;
integerExpr: NumberLiteral+;

// 类型
typeNotNull:
typeAny
| typeTuple
| typeArray
| typeList
| typeSet
| typeDictionary
| typeChannel
| typeBasic
| typePackage
| typeFunction
;

typeReference: Bang (typeNotNull | typeNullable);
typeNullable: Question typeNotNull;
typeType: typeNotNull | typeNullable | typeReference;

typeTuple: left_paren typeType (more typeType)+ right_paren;
typeArray: Left_Brack Colon Right_Brack typeType;
typeList: Left_Brack Right_Brack typeType;
typeSet: Left_Brack typeType Right_Brack;
typeDictionary: Left_Brack typeType Right_Brack typeType;
typeChannel: Left_Brack Right_Arrow Right_Brack typeType;
typePackage: nameSpaceItem (templateCall)? ;
typeFunction: typeFunctionParameterClause t=(Right_Arrow|Right_Flow) New_Line* typeFunctionParameterClause;
typeAny: TypeAny;

// 函数类型参数
typeFunctionParameterClause: left_paren typeType? (more typeType)*  right_paren;

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
| t=TypeByte
;
// nil值
nilExpr: NilLiteral;
// bool值
boolExpr: t=TrueLiteral|t=FalseLiteral;

judgeType: op=(Equal_Equal|Not_Equal) Colon;
judge: op=(Or | And | Equal_Equal | Not_Equal | Less_Equal | Greater_Equal | Less | Greater) (New_Line)?;
assign: op=(Equal | Add_Equal | Sub_Equal | Mul_Equal | Div_Equal | Mod_Equal) (New_Line)?;
add: op=(Add | Sub) (New_Line)?;
mul: op=(Mul | Div | Mod) (New_Line)?;
pow: op=(Pow | Root | Log) (New_Line)?;
call: op=Dot (New_Line)?;
wave: op=Wave;

id: (idItem)+;

idItem: op=(IDPublic|IDPrivate)
|typeBasic
|typeAny
|linqKeyword
;

end: Semi | New_Line ;
more: Comma  New_Line* ;

left_brace: Left_Brace  New_Line*;
right_brace:  New_Line* Right_Brace;

left_paren: Left_Paren;
right_paren: Right_Paren;

left_brack: Left_Brack  New_Line*;
right_brack:  New_Line* Right_Brack;
