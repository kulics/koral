lexer grammar BridgeLexer;

Data: 'data';
List: 'list';
Map: 'map';
Int: 'int';
Bool: 'bool';
String: 'string';
Float: 'float'; 
Any: 'any';

Permission: 'permission';
Read: 'read';
Write: 'write';

With: 'with';
Get: 'get'; 
Post: 'post';
Put: 'put';
Delete: 'delete';

Query: 'query';

Function: 'function';
Return: 'return';

Equal_Equal:        '==';
Less_Equal:         '<=';
Greater_Equal:      '>=';
Not_Equal:          '><';

Dot: '.';
Comma: ',';
Equal: '=';
Less: '<';
Greater: '>';
Semi: ';';
Colon: ':';

Left_Paren:             '(';
Right_Paren:             ')';
Left_Brace:             '{';
Right_Brace:             '}';
Left_Brack:             '[';
Right_Brack:             ']';

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
Xor:    '^';

NumberLiteral: DIGIT+ ; // 整数
fragment DIGIT: [0-9] ;   // 单个数字
TextLiteral: '"' ('\\' [btnfr"\\] | .)*? '"'; // 文本
CharLiteral: '\'' ('\\\'' | '\\' [btnfr\\] | .)*? '\''; // 单字符
IDPrivate: '_' [a-zA-Z0-9_]+; // 私有标识符
IDPublic: [a-zA-Z] [a-zA-Z0-9_]*; // 公有标识符
Discard: '_'; // 匿名变量

Big_Big_Comment: '###' .*? '###' -> skip; // 可嵌套注释
Big_Comment: '##' .*? '##' -> skip; // 可嵌套注释
Comment: '#' .*? '#' -> skip; // 注释

New_Line: '\n'; 
//WS: (' ' |'\t' |'\n' |'\r' )+ -> skip ;

WS: [ \t]+ -> skip; // 空白， 后面的->skip表示antlr4在分析语言的文本时，符合这个规则的词法将被无视

