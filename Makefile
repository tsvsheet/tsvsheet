.DEFAULT_GOAL := help

# tsvsheet — the one normative grammar for the .tsvt template language,
# generated to every target language so implementations parse from a single
# source of truth.
#
# TsvsheetLexer.g4 + TsvsheetParser.g4 are the source of truth (SPECIFICATION.md).
# This Makefile compiles them with ANTLR4 (the up.grammar model): the org tree is
# mounted at /work, so `make go` writes the generated Go parser DIRECTLY into the
# sibling go-tsvsheet/internal/grammar — never hand-copied. Languages without a
# sibling implementation yet still emit into gen/<lang>/ for a future lift. The
# Java/ANTLR toolchain is isolated in Docker; generated code is committed in each
# implementation, so their normal builds stay toolchain-free.

MAKEFILE_DIR := $(patsubst %/,%,$(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
ORG          := $(realpath $(MAKEFILE_DIR)/..)
ANTLR_IMAGE  := tsvsheet-antlr
LEXER        := TsvsheetLexer.g4
PARSER       := TsvsheetParser.g4

# The org tree is mounted at /work so a target can write into a sibling repo.
RUN := docker run --rm -v "$(ORG)":/work -w /work/tsvsheet $(ANTLR_IMAGE)

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  %-10s %s\n", $$1, $$2}'

.PHONY: image
image: docker/antlr/Dockerfile ## Build the pinned ANTLR4 generator image
	docker build -t $(ANTLR_IMAGE) docker/antlr

.PHONY: gen
gen: go python js java cpp ## Generate every stock-ANTLR target into gen/<lang>/

.PHONY: go
GO_OUT     := /work/go-tsvsheet/internal/grammar
GO_OUT_ABS := $(ORG)/go-tsvsheet/internal/grammar
go: image ## Generate the Go parser directly into ../go-tsvsheet/internal/grammar
	$(RUN) -Dlanguage=Go -package tsvsheetgrammar -o $(GO_OUT) $(LEXER)
	$(RUN) -Dlanguage=Go -visitor -package tsvsheetgrammar -lib $(GO_OUT) -o $(GO_OUT) $(PARSER)
	gofmt -w $(GO_OUT_ABS)
	rm -f $(GO_OUT_ABS)/*.interp $(GO_OUT_ABS)/*.tokens

.PHONY: python
python: image ## Generate the Python 3 parser into gen/python
	$(RUN) -Dlanguage=Python3 -o gen/python $(LEXER)
	$(RUN) -Dlanguage=Python3 -visitor -lib gen/python -o gen/python $(PARSER)

.PHONY: js
js: image ## Generate the JavaScript parser into gen/js
	$(RUN) -Dlanguage=JavaScript -o gen/js $(LEXER)
	$(RUN) -Dlanguage=JavaScript -visitor -lib gen/js -o gen/js $(PARSER)

.PHONY: java
java: image ## Generate the Java parser into gen/java
	$(RUN) -Dlanguage=Java -package com.tsvsheet.tsvsheetgrammar -o gen/java $(LEXER)
	$(RUN) -Dlanguage=Java -visitor -package com.tsvsheet.tsvsheetgrammar -lib gen/java -o gen/java $(PARSER)

.PHONY: cpp
cpp: image ## Generate the C++ parser into gen/cpp (ANTLR has no plain-C target)
	$(RUN) -Dlanguage=Cpp -o gen/cpp $(LEXER)
	$(RUN) -Dlanguage=Cpp -visitor -lib gen/cpp -o gen/cpp $(PARSER)

.PHONY: clean
clean: ## Remove generated parsers
	rm -rf gen
