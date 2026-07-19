/*
 * TsvsheetParser.g4 — the parser for tsvsheet (with TsvsheetLexer.g4); the
 * executable form of SPECIFICATION.md §4–§5.
 *
 * A `.tsvt` file IS the spreadsheet: a TAB-separated grid whose cells are
 * literal values or `=formulas`. The grid — lines, TABs, and literal cells — is
 * plain TSV split by the host, NOT parsed here; this grammar defines only the
 * FORMULA expression that follows a cell's leading `=`. The entry rule is
 * `expression`.
 *
 * WHAT THE GRAMMAR DOES vs DOES NOT do (grammar-first, semantics layered):
 *  - It recognizes the expression sublanguage — Excel-faithful operators
 *    (arithmetic, power `^`, text concat `&`, postfix percent `%`, comparison),
 *    A1 cell and range references, function calls, and number / string /
 *    boolean / error-value literals — precisely.
 *  - It does NOT resolve references to values, evaluate operators, order the
 *    dependency graph, or propagate error values — that is the computation model
 *    (§7), layered by an implementation over this parse tree.
 *  - Function-NAME identity (`if` ≡ `IF`, `sum`) is case-insensitive and resolved
 *    semantically.
 */
parser grammar TsvsheetParser;

options { tokenVocab=TsvsheetLexer; }

// ===== Formula expression sublanguage (§5) ================================
//
// Excel precedence, tightest first: grouping, postfix percent, power (right-
// associative), unary sign, multiplicative, additive, text concatenation,
// comparison, and the pipe loosest of all. Direct left recursion is resolved
// by ANTLR4 in declaration order.
//
// The pipe is PURE SUGAR over a function call (§5.4): `x | f(a)` is exactly
// `f(x, a)` — an implementation normalizes it at expression build, so
// evaluation only ever sees function application. The right-hand side is a
// functionCall, never a general expression: that keeps the chain unambiguous
// and makes `x | wc` (no parentheses) a syntax error by construction.
expression
    : LPAREN expression RPAREN                               # parenExpr
    | expression PERCENT                                     # percentExpr
    | <assoc=right> expression CARET expression              # powExpr
    | op=(PLUS | DASH) expression                            # unaryExpr
    | expression op=(STAR | SLASH) expression                # mulExpr
    | expression op=(PLUS | DASH) expression                 # addExpr
    | expression AMP expression                              # concatExpr
    | expression op=(EQ | NE | LT | LE | GT | GE) expression # compareExpr
    | expression PIPE functionCall                           # pipeExpr
    | functionCall                                           # callExpr
    | reference                                              # refExpr
    | NUMBER                                                 # numberExpr
    | STRING                                                 # stringExpr
    | (TRUE | FALSE)                                         # boolExpr
    | ERRORCONST                                             # errorExpr
    ;

// A call: `name( arg, … )`. The name is a NAME (`sum`) or an all-caps COL
// (`IF`), optionally with a trailing digit group so digit-bearing names lex
// correctly (`atan2`, `log10`) despite NAME/COL being letters-only.
functionCall : (NAME | COL) NUMBER? LPAREN argList? RPAREN ;

argList : expression (COMMA expression)* ;

// ===== A1 references (§4) =================================================
//
// A cell — a column letter and a 1-based row number, each optionally $-absolute
// — or a rectangular range of two cells. An optional `"file"!` qualifier reads
// the cell(s) from another sheet by path (relative, bare, or absolute); the
// same qualifier scopes the whole range.
reference : sheetQualifier? cellRef (COLON cellRef)? ;

sheetQualifier : STRING BANG ;

cellRef : DOLLAR? COL DOLLAR? NUMBER ;
