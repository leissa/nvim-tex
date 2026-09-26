NVIM ?= nvim

# Pinned so a parser rebuild does not silently change what the tests exercise.
# ABI 14 is understood by every Neovim from 0.10 on.
TS_LATEX_REV ?= fa8df448fc2c0192a8c2f8cfc97de53cb2b4ecb9
TS_ABI ?= 14

DEPS := .deps
PARSER := $(DEPS)/parser/latex.so

.PHONY: test parser doc clean

## Run the whole suite, or a single file with
## `TEST_FILE=tests/qf_spec.lua make test`. Specs that need the `latex` parser
## skip when it is missing; `make parser` builds one into .deps.
test:
	$(NVIM) --headless --clean -u tests/minimal_init.lua \
		-c "lua require('tests.runner').main()"

## Build the `latex` tree-sitter parser into .deps/parser, which
## tests/minimal_init.lua puts on the runtimepath.
parser: $(PARSER)

$(PARSER):
	@command -v tree-sitter >/dev/null || \
		{ echo "the tree-sitter CLI is required: npm install -g tree-sitter-cli"; exit 1; }
	rm -rf $(DEPS)/tree-sitter-latex
	git clone --filter=blob:none https://github.com/latex-lsp/tree-sitter-latex \
		$(DEPS)/tree-sitter-latex
	git -C $(DEPS)/tree-sitter-latex checkout --quiet $(TS_LATEX_REV)
	cd $(DEPS)/tree-sitter-latex && tree-sitter generate --abi $(TS_ABI)
	mkdir -p $(DEPS)/parser
	$(CC) -O2 -fPIC -shared -I $(DEPS)/tree-sitter-latex/src -o $@ \
		$(DEPS)/tree-sitter-latex/src/parser.c $(DEPS)/tree-sitter-latex/src/scanner.c

doc:
	$(NVIM) --headless --clean -c 'helptags doc' -c q

clean:
	rm -rf $(DEPS) doc/tags
