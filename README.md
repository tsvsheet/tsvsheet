# tsvsheet

> **A spreadsheet for plain text.** A `.tsvt` file _is_ the spreadsheet — a tab-separated grid whose cells are values or `=formulas` that address other cells in A1 notation, computed by a processor, versioned as text, diffed line by line.

A `.tsvt` is one grid: each cell is a literal value, or a formula (a cell beginning with `=`) that computes from other cells referenced by their A1 address (`B2`, `D2:D5`) — exactly like a conventional spreadsheet, kept as plain text. Because fields are tab-separated, a formula like `=if(A1, C3, D3)` is written verbatim — no quoting, no escaping. That is the reason the language is TSV, not CSV.

Columns below are space-aligned for readability; on disk every field is separated by a single **TAB**.

```text
Student   Math   Reading   Science   Average                 Pass
Alice     85     90        78        =round(avg(B2:D2), 1)   =if(E2 >= 70, 1, 0)
Bob       72     68        80        =round(avg(B3:D3), 1)   =if(E3 >= 70, 1, 0)
```

This repository is the **grammar-first** home of the language: the ANTLR4 grammar is the source of truth, and language implementations are generated from it.

- **Grammar:** [TsvsheetParser.g4](TsvsheetParser.g4) · [TsvsheetLexer.g4](TsvsheetLexer.g4)
- **Specification:** [SPECIFICATION.md](SPECIFICATION.md)
- **Generate a parser:** `make image && make go` (or `python`, `js`, `java`, `cpp`) — output lands in `gen/<lang>/` to lift into an implementation repo. `make help` lists targets. The Java/ANTLR toolchain is isolated in Docker; nothing else is needed to regenerate.

**Status:** Draft 0.1.0 — the single-file A1 spreadsheet model ([SPECIFICATION.md](SPECIFICATION.md)); an earlier draft misread the 2011 `csvsheet` design as a two-file worksheet. The grammar is now the A1 language: a formula expression sublanguage with Excel-faithful operators (`^`, `&`, postfix `%`, `TRUE`/`FALSE` and error-value literals) over A1 cell and range references; the legacy worksheet/section/modifier forms have been pruned. Sections marked **[open]** in the spec were underspecified in the source and are recorded as open questions, never filled by invention.
