lexer grammar XsLexer;

LinqFrom: 'from';
LinqBy: 'by';
LinqSelect: 'select';
LinqWhere: 'where';
LinqGroup: 'group';
LinqInto: 'into';
LinqOrderby: 'orderby';
LinqJoin: 'join';
LinqLet: 'let';
LinqIn: 'in';
LinqOn: 'on';
LinqEquals: 'equals';
LinqAscending: 'ascending';
LinqDescending: 'descending';

Event: 'Event';

Pow:    '**';
Root:   '//';
Log:    '%%';

Add_Equal:         '+=';
Sub_Equal:         '-=';
Mul_Equal:         '*=';
Div_Equal:         '/=';
Mod_Equal:         '%=';
Colon_Equal:       ':=';

Equal_Equal:        '==';
Less_Equal:         '<=';
Greater_Equal:      '>=';
Not_Equal:          '><';

Dot_Dot_Dot: '...';
Dot_Dot: '..';
Dot: '.';

Comma: ',';

Right_Arrow: '->';
Left_Arrow: '<-';

Right_Flow: '~>';
Left_Flow: '<~';

Equal: '=';

Less: '<';
Greater: '>';

Semi: ';';

Left_Paren:             '(';
Right_Paren:             ')';
Left_Brace:             '{';
Right_Brace:             '}';
Left_Brack:             '[';
Right_Brack:             ']';

Colon_Colon: '::';
Colon: ':';

Question: '?';

At: '@';

Bang: '!';

Wave: '~';

Add:    '+';
Sub:    '-';
Mul:    '*';
Div:    '/';
Mod:    '%';
Slash:  '\\';

And:    '&';
Or:     '|';

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
TrueLiteral: 'True';
FalseLiteral: 'False';
UndefinedLiteral: 'Undefined';

NumberLiteral: DIGIT+ ; // 整数
fragment DIGIT: [0-9] ;   // 单个数字
TextLiteral: '"' ('\\' [btnfr"\\] | .)*? '"'; // 文本
CharLiteral: '\'' ('\\' [btnfr\'\\] | .)*? '\''; // 单字符
IDPrivate: '_' [a-zA-Z0-9_]+; // 私有标识符
IDPublic: [a-zA-Z] [a-zA-Z0-9_]*; // 公有标识符
Discard: '_'; // 匿名变量

Big_Big_Comment: '###' .*? '###' -> skip; // 可嵌套注释
Big_Comment: '##' .*? '##' -> skip; // 可嵌套注释
Comment: '#' .*? '#' -> skip; // 注释

New_Line: '\n'; 
//WS: (' ' |'\t' |'\n' |'\r' )+ -> skip ;

WS: [ \t]+ -> skip; // 空白， 后面的->skip表示antlr4在分析语言的文本时，符合这个规则的词法将被无视

