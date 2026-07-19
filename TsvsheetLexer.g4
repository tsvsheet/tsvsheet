/*
 * TsvsheetLexer.g4 — the lexer for tsvsheet (with TsvsheetParser.g4, the
 * executable form of SPECIFICATION.md). ANTLR requires the file name to match
 * the grammar name, hence the CamelCase.
 *
 * A `.tsvt` file IS the spreadsheet — a TAB-separated grid whose cells are
 * literal values or `=formulas`. The grid itself (lines, tabs, literal cells) is
 * plain TSV split by the host; only the FORMULA expression after a cell's
 * leading `=` is parsed here. So this lexer tokenizes a single formula: numbers,
 * strings, boolean and error-value literals, A1 references, operators, and
 * function names. A single ASCII space is insignificant padding and is skipped.
 *
 * GRAMMAR-FIRST: function-NAME identity (`if` ≡ `IF`) and the meaning of an A1
 * reference are resolved semantically by an implementation walking the parse
 * tree, never here. Boolean and error-value literals are keyword tokens.
 */
lexer grammar TsvsheetLexer;

// ---- comparison operators (longer alternative first) --------------------
GE      : '>=' ;
LE      : '<=' ;
NE      : '<>' ;
GT      : '>'  ;
LT      : '<'  ;

// ---- boolean literals (keywords, before COL so they are not column letters) --
TRUE    : 'TRUE'  ;
FALSE   : 'FALSE' ;

// ---- error-value literals (closed set, §6; before any other `#`-lexeme) ------
ERRORCONST
    : '#' ( 'N/A' | 'REF!' | 'VALUE!' | 'NAME?' | 'DIV/0!' | 'NUM!' | 'NULL!' | 'SPILL!' | 'CIRC!' ) ;

// ---- operators & punctuation --------------------------------------------
EQ      : '='  ;   // equality (§5)
LPAREN  : '('  ;
RPAREN  : ')'  ;
COLON   : ':'  ;   // range: A1:C3
COMMA   : ','  ;   // argument separator
DOLLAR  : '$'  ;   // absolute marker: $B$2
STAR    : '*'  ;   // multiply
PLUS    : '+'  ;   // add / unary plus
DASH    : '-'  ;   // subtract / unary minus
SLASH   : '/'  ;   // divide
PERCENT : '%'  ;   // postfix percent: 50%
CARET   : '^'  ;   // power: 2^8
AMP     : '&'  ;   // text concatenation: A1 & B1
BANG    : '!'  ;   // sheet qualifier: "other.tsvt"!B2
PIPE    : '|'  ;   // pipe: A1 | round(2) ≡ round(A1, 2)

// ---- lexemes ------------------------------------------------------------
NUMBER  : [0-9]+ ('.' [0-9]+)? ;   // numeric literal or A1 row number
COL     : [A-Z]+ ;                 // column letter(s): A, B, AA — uppercase A1 style
NAME    : [A-Za-z]+ ;              // function name (case-insensitive): sum, IF
STRING  : '"' ~["\r\n]* '"' ;      // string literal

// ---- trivia -------------------------------------------------------------
WS      : ' '+ -> skip ;           // insignificant padding inside a formula
