parser grammar BridgeParser;

options { tokenVocab=BridgeLexer; }

program: statement+;

statement: dataStatement | functionStatement;

dataStatement: Data id left_brack propertyStatement* right_brack dataExtraSupport* end;

propertyStatement: (annotationSupport)* id typeType end;

annotationSupport: At id;

dataExtraSupport:
queryStatement|
withStatement|
permissionStatement;

withStatement: With left_brack withSupport right_brack;

withSupport:
Get|
Post|
Put|
Delete;

permissionStatement: Permission left_brack permissionSupport right_brack;

permissionSupport: id Colon ;

queryStatement: Query left_brack querySupport right_brack;

querySupport: id Colon ;

functionStatement: Function id left_paren right_paren Return typeType end;

parameterList: parameter (Comma parameter)*;

parameter: id typeType;

typeType:
typeList|
typeMap|
typeBasic|
typeClass;

typeList: List Left_Brack typeType Right_Brack;
typeMap: Map Left_Brack typeType Comma typeType Right_Brack;
typeClass: id;
// 基础类型名
typeBasic:
t=Int
| t=Float
| t=String
| t=Bool
| t=Any
;

id: op=(IDPublic|IDPrivate);

end: Semi | New_Line ;
more: Comma  New_Line* ;

left_brace: Left_Brace  New_Line*;
right_brace:  New_Line* Right_Brace;

left_paren: Left_Paren;
right_paren: Right_Paren;

left_brack: Left_Brack  New_Line*;
right_brack:  New_Line* Right_Brack;