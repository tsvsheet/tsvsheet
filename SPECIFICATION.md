# tsvsheet — Language Specification

**Status:** Draft (2026-07-14). Corrected to the **single-file A1 spreadsheet** model. An earlier salvage of the 2011 `csvsheet` working draft misread it as a _two-file worksheet_ — raw data in a `.tsv` and a separate `.tsvt` "template" of `=header`/`=body`/`=final` sections, structural modifiers, and row-relative references. That is not what tsvsheet is. A `.tsvt` **is** the spreadsheet: one grid, cells holding values or formulas, formulas addressing other cells by A1 reference, computed in place — exactly like a conventional spreadsheet, kept as plain text. Sections marked **[open]** were genuinely underspecified in the source and are recorded as open questions rather than invented.

## 1. Concept

A **`.tsvt` file is a spreadsheet**: a rectangular grid of cells, one row per line, cells separated by TAB (`U+0009`). Each cell is one of two things:

- a **literal value** — text or a number, stored verbatim; or
- a **formula** — a cell whose text begins with `=`, an expression that computes a value from literals and from _other cells_, referenced by their A1 address (`B2`, `D2:D5`).

A processor reads the grid, evaluates every formula, and emits the **computed grid** (again as TSV) with each formula replaced by its value. Data and computation live together in one file, cell by cell, the way a spreadsheet has always worked — and because the file is plain text, it versions and diffs line by line.

Throughout this spec, code blocks show columns **space-aligned for readability**; on disk every field is separated by a single **TAB**.

## 2. Why TSV, not CSV

The tab delimiter is the reason the language is clean:

- **No formula quoting.** A tab cannot occur inside a formula, so `=if(A1, C3, D3)`, `=sum(A1:A10)`, and any comma-bearing expression are written verbatim. The 2011 CSV design had to redefine CSV quoting (wrapping comma-bearing formulas in `()` or `"…"` and escaping a literal leading `=` as `\=`); none of that exists here.
- **No delimiter ambiguity.** Values may contain commas, spaces, and parentheses freely.
- **A literal leading `=`** is the _only_ thing that makes a cell a formula, so a value that must begin with `=` is the one case a producer escapes; everything else is verbatim.

CSV input MAY be accepted as a compatibility dialect, but TSV is the canonical form and the only form in which the no-escaping guarantee holds.

## 3. Cells: literals and formulas

Every TAB-delimited field of every line is a **cell**. Its classification is purely lexical:

- A field whose text **begins with `=`** is a **formula**; the `=` is the marker and the rest is the expression (§5).
- Any other field is a **literal**, stored exactly as written — `Alice`, `85`, `4.50`, or the empty string for an empty cell.

Literals are never parsed as expressions and never coerced on input; a literal `4.50` stays `4.50` in the output. A formula that reads a literal interprets it as a number where the operation is numeric (`=A1+1` reads `4.50` as `4.5`) and as text where it is textual.

**Comment lines.** Two kinds of whole-line comment are skipped when reading the grid and **do not occupy a row** (so A1 addressing counts only data rows): the **first line** if it begins with `#!` (a shebang, so a `.tsvt` can be `chmod +x` and run via `#!/usr/bin/env tsvsheet`), and **any line** beginning with `#` (hash-space). Because the marker is hash-_space_, an error-value cell such as `#N/A` or `#REF!` in the first column (hash then a non-space) is ordinary data, not a comment. Comments are a read-time convenience and are not preserved when a sheet is re-serialized. **[open]** Whether comments should round-trip, and inline (end-of-cell) comments, are not specified.

## 4. A1 references

A formula addresses other cells by **A1 reference**, the conventional spreadsheet scheme:

- **Cell** — a column letter followed by a 1-based row number: `A1`, `B2`, `D5`, `AA10`. Column `A` is the first column; row `1` is the first line.
- **Absolute marker** — a `$` may precede the column, the row, or both (`$B$2`, `$B2`, `B$2`). In a flat single-file grid every reference is already absolute, so `$` is accepted and carries no positional difference; it is retained for familiarity and for tools that round-trip Excel-style addresses.
- **Range** — two cell references separated by `:` denote the **rectangle** of cells between them, inclusive: `D2:D5` (a column span), `A1:C3` (a 3×3 block). Ranges are the argument form for aggregate functions (`=sum(D2:D5)`).
- **Sheet qualifier** — a reference may be prefixed by `"path"!` to read the cell(s) from **another sheet by file path**: `"rates.tsvt"!B2`, `"rates.tsvt"!A1:A9`, `"../shared/tax.tsvt"!C3`, `"/etc/budget.tsvt"!A1`. The path is a double-quoted string (so any filename or path is written verbatim) followed by `!`; it may be a **bare filename** (no directory), a **relative path**, or an **absolute path**. A bare or relative path resolves against the _referencing sheet's own directory_. The same qualifier scopes a whole range. Reading `"file"!A1` computes the target sheet and takes cell A1's value; the target's own formulas (including its own cross-sheet references) resolve normally. An unresolvable path — or a context with no file loader (e.g. a piped stdin) — is `#REF!`; a chain of sheets that references back to one already being computed is `#CIRC!` (§7). Cross-sheet references address another sheet, so a structural edit (row/column insert or delete) in the referencing sheet never shifts them.
  - **[open] Confinement is a host policy.** How far a reference may reach is up to the implementation, not the language. A host **should** default to confining references within the referencing sheet's directory tree (rejecting an absolute path, a `..` escape, or a symlink out as `#REF!`) and offer an explicit opt-in for wider access, so that opening an untrusted sheet cannot read arbitrary files. (The Go implementation confines via `os.Root` by default and unlocks any path with `--allow-any-paths`.)

A reference to a position **outside the grid** resolves to the error value `#REF!` (§6). There is no row-relative, whole-column, header-named, or numeric-index reference form: those belonged to the misread worksheet model and are not part of the A1 language. (The published grammar still parses several of them — see §11.)

## 5. Formula expression language

A formula is `=` followed by an **expression**. The normative form is [TsvsheetParser.g4](TsvsheetParser.g4) (rule `expression`); this section is its prose.

### 5.1 Operands

An operand is a **number**, a **string literal**, a **boolean literal**, an **error-value literal**, a **cell or range reference** (§4), or a **function call**. A number is `[0-9]+` with an optional `.` fraction; a string literal is double-quoted (`"…"`); a boolean literal is `TRUE` or `FALSE`; an error-value literal is one of the §6 codes written verbatim (`#N/A`, `#REF!`, …).

### 5.2 Operators and precedence

The operators are Excel-faithful; they bind tightest-first:

| Level | Operators                          | Associativity |
| ----- | ---------------------------------- | ------------- |
| 1     | `( … )` grouping                   | —             |
| 2     | postfix `%` (percent: `50%` = 0.5) | —             |
| 3     | `^` (power)                        | right         |
| 4     | unary `-`, unary `+`               | right         |
| 5     | `*` `/`                            | left          |
| 6     | binary `+` `-`                     | left          |
| 7     | `&` (text concatenation)           | left          |
| 8     | `=` `<>` `<` `<=` `>` `>=`         | left          |
| 9     | `\|` (pipe, §5.4)                  | left          |

So `A1 + B1 * C1` groups as `A1 + (B1 * C1)`, `-2^2` is `-(2^2)`, and comparisons yield the boolean `TRUE` or `FALSE`. There is no binary `%` (modulo is the `mod(a, b)` function); `&` joins the text forms of its operands.

### 5.3 Function calls

A function call is `name( arg, … )`; each argument is an expression, including a range (`sum(D2:D5)`). Function **names are case-insensitive** (`if` ≡ `IF`). The grammar fixes the _call syntax_; the defined set is semantic. The reference set is:

| Function | Result |
| --- | --- |
| `sum(range…)` `avg(range…)` `min(range…)` `max(range…)` `count(range…)` | aggregates over the cells of the argument(s) |
| `round(x)` / `round(x, n)` | `x` rounded to `n` decimal places (0 if omitted) |
| `abs(x)` `len(x)` | absolute value; text length |
| `mod(a, b)` | remainder of `a / b` (replaces the retired binary `%`) |
| `concat(a, b, …)` | textual concatenation |
| `if(cond, then, else)` | `then` when `cond` is truthy, else `else` |
| `output(expr)` `sheet(path, arg…)` `input(n)` | embed another sheet as a function (§8) |

An unknown function name computes to `#NAME?` (§6) and is flagged by a static check.

### 5.4 The pipe operator

`expr | name(arg, …)` is **sugar for a function call**: the piped expression becomes the call's **first argument** — `A1 | round(2)` is exactly `round(A1, 2)`. The right-hand side must be a function call in the §5.3 form, parentheses included (`A1 | len` is a syntax error); the operator is left-associative, so chains fold left — `A2:A10 | sort() | unique() | count()` is `count(unique(sort(A2:A10)))`. It binds loosest of all operators (level 9), so the entire preceding expression is the piped value: `A1 & B1 | len()` is `len(A1 & B1)`.

There is **no pipe at evaluation**. A processor normalizes the pipe to its equivalent call when it builds the expression, so the §7 computation model — dependency graph, memoization, error propagation — is unchanged and there is exactly one execution path: function application. An error value piped into a call propagates exactly as it would as an argument (§6). The two spellings are the same formula; a processor that re-emits formula text (a trace, a structural edit) preserves the author's spelling.

## 6. Values and error values

A computed cell is a **number**, **text**, or one of the **error values**, which propagate through any expression that reads them:

| Error | Arises when |
| --- | --- |
| `#REF!` | a reference resolves outside the grid, or an embedded sheet cannot be resolved (§8) |
| `#DIV/0!` | division or modulo by zero |
| `#CIRC!` | a formula participates in a reference cycle, within a sheet or across embedded sheets (§8) |
| `#VALUE!` | an operation receives an operand of the wrong kind |
| `#NAME?` | a call names an unknown function |
| `#IMPORT!` | an `IMPORT*` fetch fails or its response is refused (§9) |

A literal cell already holding one of these strings round-trips as that error value.

## 7. Computation model

The processor evaluates the grid as a **dependency graph**, not line by line:

1. Parse every cell; compile each formula's expression.
2. For each formula, resolve its cell references and evaluate, computing referenced cells first. Results are **memoized**, so each cell is computed once regardless of how many formulas read it.
3. A reference **cycle** (a cell that, transitively, depends on itself) yields `#CIRC!` for the cells on the cycle.
4. Emit the computed grid: literal cells verbatim, formula cells replaced by their value.

Order of appearance does not matter: `C1 = =B1*2` may sit to the left of `B1 = =A1+10`; both resolve correctly because evaluation follows dependencies. This is ordinary spreadsheet recalculation, not the row-relative, top-to-bottom pass of the misread worksheet model.

## 8. Embedded sheets (a spreadsheet as a function)

A cell may embed **an entire other sheet**: its value is that sheet's computed output. This makes a `.tsvt` reusable as a function — parameterised, versioned as text, and composed like any cell. Three builtins express it, all ordinary function calls (§5.3), so the grammar is unchanged and the behaviour is semantic (layered by an implementation over the parse tree).

| Builtin | Result |
| --- | --- |
| `output(expr)` | Marks the cell it occupies as the sheet's single **output**; its value is `expr`. A sheet with an `output` cell can be embedded. |
| `sheet(path, arg…)` | Loads the sheet at `path`, computes it, and yields its `output` cell's value. The extra arguments are passed into the sub-sheet. |
| `input(n)` | Inside an embedded sheet, resolves to the `n`-th (1-based) argument the embedding `sheet(…)` call passed. |

A reusable `discount.tsvt` reads its inputs and declares an output:

```text
price       qty         subtotal
=input(1)   =input(2)   =A2*B2
discount    0.1         =C2*(1-B3)
=output(C3)
```

and another sheet embeds it, once per row — the whole sub-sheet computing to the single cell:

```text
Order     Total
Widgets   =sheet("discount.tsvt", 100, 3)    → 270
Gadgets   =sheet("discount.tsvt", 50, 10)    → 450
```

Rules:

- **Exactly one output.** A sheet with no `output` cell, or with more than one, is `#REF!` when embedded.
- **Path resolution and containment.** `path` resolves relative to the embedding sheet's own directory and must stay within the root the frontend fixes (typically the top sheet's directory); an escape (`..`, a symlink out) or an unresolved path is `#REF!`. Computation is filesystem-free — the host injects the loader — so a context with no loader (for example a piped stdin) resolves `sheet(…)` to `#REF!`.
- **Cross-sheet cycles.** A sheet that transitively embeds itself is `#CIRC!`, exactly like an intra-sheet reference cycle (§7).
- **[open] Named or multiple outputs.** Only a single positional output per sheet is defined; named outputs, or a sheet exposing several outputs, are not specified.

## 9. Imported values

A cell may pull **external data over HTTPS** into the grid. Five builtins express it, one per result shape — ordinary function calls (§5.3), so the grammar is unchanged; each takes a single URL argument:

| Builtin | Requests (preferred media type) | Result |
| --- | --- | --- |
| `importcell(url)` | `application/vnd.tsvsheet.cell+tsv` | a single scalar value |
| `importrow(url)` | `application/vnd.tsvsheet.row+tsv` | a 1×N row that spills horizontally |
| `importcolumn(url)` | `application/vnd.tsvsheet.column+tsv` | an N×1 column that spills vertically |
| `importrange(url)` | `application/vnd.tsvsheet.range+tsv` | an R×C block that spills |
| `importsheet(url)` | `application/vnd.tsvsheet+tsv` | a whole external grid |

Rules:

- **Accepted response types.** The request advertises the function's vendor media type preferred, with the standard tabular types admitted: `Accept: <vendor>, text/tab-separated-values;q=0.9, text/csv;q=0.8`. The response is ingested only when its `Content-Type` base — parameters such as `charset` stripped, case ignored — is the vendor type, `text/tab-separated-values`, or `text/csv`. Any other type (HTML, JSON, `text/plain`, …) is `#IMPORT!`. A TSV or vendor-typed body parses as a TSV fragment; a `text/csv` body parses as RFC 4180.
- **Values only.** An import ingests **computed values, never formulas**: a leading `=` in an imported cell is literal text, never evaluated. An imported value cannot trigger a further fetch.
- **Shape is strict.** A `cell` response must be exactly one cell, a `row` exactly one line, a `column` one value per line, a `range`/`sheet` a non-empty rectangle. A shape mismatch is `#IMPORT!`, never a best-effort salvage.
- **Every failure is `#IMPORT!`.** Feature disabled, host not allowed, non-2xx status, unaccepted content type, malformed body, shape mismatch, oversize response, timeout — all surface as the one error value; a processor's trace facility may carry the specific reason.
- **Off by default.** A processor performs no network I/O unless its operator explicitly enables imports and allowlists the target hosts; nothing inside a `.tsvt` can enable the feature or widen the allowlist. Transport is `https` (with verified TLS) except loopback targets; responses are bounded in size and time.
- **Not clock-volatile.** Imports do not refresh with `now()`-style recomputation; fetched values are cached and re-fetched only on an explicit refresh.

## 10. Worked example

A `grades.tsvt` spreadsheet — literal data plus per-row formulas:

```text
Student   Math   Reading   Science   Average                 Result
Alice     85     90        78        =round(avg(B2:D2), 1)   =if(E2 >= 70, "Pass", "Fail")
Bob       72     68        80        =round(avg(B3:D3), 1)   =if(E3 >= 70, "Pass", "Fail")
Carol     95     88        91        =round(avg(B4:D4), 1)   =if(E4 >= 70, "Pass", "Fail")
Dave      60     55        70        =round(avg(B5:D5), 1)   =if(E5 >= 70, "Pass", "Fail")
```

computes to:

```text
Student   Math   Reading   Science   Average   Result
Alice     85     90        78        84.3      Pass
Bob       72     68        80        73.3      Pass
Carol     95     88        91        91.3      Pass
Dave      60     55        70        61.7      Fail
```

Each `Average` cell reads its row's three scores; each `Result` cell reads the `Average` computed in the same row. A formula that referenced a cell off the grid (say `=E6` on the last row) would compute to `#REF!`.

## 11. Scope and open items

- **`#VALUE!` conditions.** The precise operand-kind rules that produce `#VALUE!` (e.g. arithmetic on text) are settled per operator by the implementation and are not yet enumerated here.
- **Function library.** The reference set of §5.3 is the starting point; a comprehensive, Excel-faithful function library (statistical, text, date, lookup, and array functions) is being built out over it in [tsvsheet/tsvsheet.go](https://github.com/tsvsheet/tsvsheet.go).

## 12. Provenance

Derived from `csvsheet` (working draft 2011-03-07), a single-file spreadsheet whose cells held values or formulas over comma-separated rows. This capture corrects an intervening draft that reinterpreted it as a two-file "worksheet" with data and a sectioned template kept apart — a reading the design does not support. Changes from the source: the TSV delimiter (eliminating the CSV formula-quoting rule), A1 references in place of the ad-hoc reference notation, an explicit dependency-graph computation model (§7), and the formula expression language (§5), which the source only exemplified. Items marked **[open]** reflect gaps left unfilled by invention. The pipe operator (§5.4) is a dated extension (2026-07-17): pure syntax over §5.3 function calls, absent from the source.
