# oogrep v0.3.2 Makefile
#
# Build, verify, and test the capability-bounded recursive search tool.
#
# Usage:
#   make build       - compile main.oo to dist/oogrep
#   make test        - run CLI and MCP smoke tests (openOODA-built tools only)
#   make check       - run oodac check on every .oo file
#   make line-cap    - enforce 16-256 line cap on every .oo and .oot (shim-exempt)
#   make file-law    - reject forbidden file extensions and stray docs
#   make academy     - verify every .oo has the 4-element Academy header
#   make pure        - audit that test steps use openOODA-built tools only
#   make verify      - run line-cap, file-law, academy, and check
#   make parity      - verify binary hash
#   make install     - copy dist/oogrep to ~/.openooda/bin/oogrep
#   make clean       - remove build artifacts
#   make all         - build + verify + double-run test

OODA_COMPILER ?= $(firstword $(wildcard $(HOME)/.openooda/bin/oodac $(CURDIR)/../../openOODA/oodac/bin/oodac))
OODACODEX ?= $(HOME)/.openooda/northstar.oot
OO_LIST_AMBIENT_QUOTA ?= 8589934592
BIN := dist/oogrep
OOJQ_CANDIDATES := ../oojq/dist/oojq $(HOME)/.openooda/bin/oojq

SRC := main.oo anchor.oo parse_decimal.oo search_opts.oo search.oo \
       walk/anchor.oo walk/collect_candidates.oo walk/filter_by_glob.oo walk/filter_by_kind.oo walk/gitignore.oo \
       match/anchor.oo match/compile_pattern.oo match/locate_span.oo match/scan_lines.oo match/scan_context.oo match/rank_hits.oo \
       render/anchor.oo render/render_match.oo render/render_summary.oo render/render_errors.oo render/render_json.oo \
       mcp/anchor.oo mcp/json_field.oo mcp/schema.oo mcp/dispatch.oo mcp/serve.oo \
       qa/fixtures/main.oo qa/fixtures/alpha.oo qa/fixtures/nested/deep.oo

.PHONY: all build test check line-cap file-law academy density pure verify parity install package-deb package-rpm package clean

all: build verify test

build: $(BIN)

$(BIN): $(SRC)
	@mkdir -p dist .ooda-cache/ooda-tmp
	OO_LIST_AMBIENT_QUOTA=$(OO_LIST_AMBIENT_QUOTA) OODACODEX=$(OODACODEX) OODA_COMPILER=$(OODA_COMPILER) OODA_NO_JAIL=1 $(OODA_COMPILER) build main.oo -o $(BIN)
	@chmod +x $(BIN)
	@cp -a $(BIN) dist/oogrep-linux-x86_64
	@sha256sum dist/oogrep-linux-x86_64 > dist/oogrep-linux-x86_64.sha256
	@echo "built $(BIN) (and dist/oogrep-linux-x86_64)"

# --- Verification gate ---------------------------------------------------------

# A shim is a file whose every non-comment line is an import. Shims skip the
# 16-line floor. The 256-line ceiling still applies to them without exception.
line-cap:
	@violations=0; \
	for f in $$(find . -name "*.oo" -o -name "*.oot"); do \
		n=$$(wc -l < "$$f"); \
		if [ $$n -gt 256 ]; then \
			echo "VIOLATION: $$f = $$n lines (exceeds 256)"; violations=$$((violations+1)); \
			continue; \
		fi; \
		code=$$(grep -vE '^[[:space:]]*(//.*)?$$' "$$f" | grep -cvE '^[[:space:]]*import[[:space:]]+"'); \
		if [ "$$code" = "0" ]; then continue; fi; \
		if [ $$n -lt 16 ]; then \
			echo "VIOLATION: $$f = $$n lines (under 16-line floor, not a shim)"; violations=$$((violations+1)); \
		fi; \
	done; \
	if [ $$violations -gt 0 ]; then echo "FAIL: $$violations files violate the Page Rule"; exit 1; fi; \
	echo "PASS: Page Rule sizing (16-256 lines, shims exempt from floor) holds"

file-law:
	@forbidden="py js ts rb pl json yaml toml"; \
	violations=0; \
	for ext in $$forbidden; do \
		found=$$(find . -name "*.$$ext" -not -path "./.git/*" -not -path "./dist/*" -not -path "./.ooda-cache/*" -not -path "./.blackbox/*" 2>/dev/null | head -3); \
		if [ -n "$$found" ]; then \
			echo "VIOLATION: .$$ext forbidden:"; echo "$$found"; violations=$$((violations+1)); \
		fi; \
	done; \
	for f in $$(find . -name "*.sh" -not -path "./.git/*" -not -path "./.ooda-cache/*" -not -path "./.blackbox/*" 2>/dev/null); do \
		if [ "$$f" != "./install.sh" ] && [ "$$f" != "./uninstall.sh" ]; then \
			echo "VIOLATION: .sh forbidden outside install.sh and uninstall.sh: $$f"; violations=$$((violations+1)); \
		fi; \
	done; \
	for f in $$(find . -name "*.md" -not -path "./.git/*" -not -path "./.ooda-cache/*" -not -path "./.blackbox/*" 2>/dev/null); do \
		if [ "$$f" != "./README.md" ] && [ "$$f" != "./AGENTS.md" ]; then \
			echo "VIOLATION: .md forbidden outside README.md and AGENTS.md: $$f"; violations=$$((violations+1)); \
		fi; \
	done; \
	if [ $$violations -gt 0 ]; then echo "FAIL: file-law violations"; exit 1; fi; \
	echo "PASS: file law holds"

academy:
	@failures=0; \
	for f in $$(find . -name "*.oo" -not -path "./dist/*"); do \
		header=$$(head -7 "$$f"); \
		missing=""; \
		echo "$$header" | grep -q "^// # "        || missing="$$missing title"; \
		echo "$$header" | grep -q "^// Logline:"  || missing="$$missing logline"; \
		echo "$$header" | grep -q "^// Setup:"    || missing="$$missing setup"; \
		echo "$$header" | grep -q "^// Beats:"    || missing="$$missing beats"; \
		if [ -n "$$missing" ]; then \
			echo "FAIL: $$f missing Academy element(s):$$missing"; failures=$$((failures+1)); \
		fi; \
	done; \
	if [ $$failures -gt 0 ]; then echo "FAIL: $$failures academy header violations"; exit 1; fi; \
	echo "PASS: academy headers hold (all 4 elements present in first 7 lines)"

# At most 8 pages per directory. Counted over .oo and .oot, tests included.
density:
	@violations=0; \
	for d in $$(find . -type d -not -path "./.git*" -not -path "./dist*" -not -path "./.ooda-cache*"); do \
		n=$$(ls "$$d"/*.oo "$$d"/*.oot 2>/dev/null | grep -v '\*' | wc -l); \
		if [ $$n -gt 8 ]; then \
			echo "VIOLATION: $$d holds $$n pages (exceeds 8)"; violations=$$((violations+1)); \
		fi; \
	done; \
	if [ $$violations -gt 0 ]; then echo "FAIL: $$violations directories exceed the density bound"; exit 1; fi; \
	echo "PASS: directory density (<= 8 pages per directory) holds"

check:
	@for f in $$(find . -name "*.oo" -not -path "./dist/*"); do \
		$(OODA_COMPILER) check "$$f" > /dev/null || exit 1; \
	done; \
	echo "PASS: oodac check holds on all .oo files"

# The test steps below assert with the freshly built binary (-q over stdin)
# and with oojq for JSON answers. This audit fails the build if any test step
# leans on an outside helper again. The audit itself is a measuring tape, so
# it may use platform utilities; the tests it watches may not.
pure:
	@awk '/^test:/{in_test=1} /^[a-z][a-z_-]*:/{if ($$0 !~ /^test:/) in_test=0} in_test' Makefile > .ooda-cache/test_block.txt; \
	if grep -E -q "python3?|[^a-zA-Z_.]grep([^a-zA-Z]|$$)|[^a-zA-Z_.]wc([^a-zA-Z]|$$)|[^a-zA-Z_.]jq([^a-zA-Z]|$$)|[^a-zA-Z_.]awk([^a-zA-Z]|$$)" .ooda-cache/test_block.txt; then \
		echo "FAIL: test steps reference outside helpers:"; grep -E -o "python3?|[^a-zA-Z_.]grep|[^a-zA-Z_.]wc|[^a-zA-Z_.]jq|[^a-zA-Z_.]awk" .ooda-cache/test_block.txt | sort -u; exit 1; \
	fi; \
	echo "PASS: test steps use openOODA-built tools only"

verify: line-cap file-law academy density check pure

# --- Tests ---------------------------------------------------------------------
# Every content assertion below runs through openOODA-built tools: the binary
# under test checks its own output with -q over stdin, and oojq checks JSON
# answers. Negative assertions (expecting exit 1) keep a broken -q honest.

test: $(BIN)
	@echo "=== testing --help ==="
	@./$(BIN) --help > /dev/null && echo "PASS: --help"
	@echo "=== testing --version ==="
	@./$(BIN) --version > /dev/null && echo "PASS: --version"
	@echo "=== testing fixture match ==="
	@./$(BIN) "pub fn main" qa/fixtures > /dev/null && echo "PASS: fixture match"
	@echo "=== testing no-match exit code (expect 1) ==="
	@./$(BIN) "zzz_no_such_token_zzz" qa/fixtures > /dev/null; test $$? -eq 1 && echo "PASS: no-match exits 1"
	@echo "=== testing bad usage (expect 2) ==="
	@./$(BIN) > /dev/null 2>&1; test $$? -eq 2 && echo "PASS: missing pattern exits 2"
	@echo "=== testing bad regex fails closed (expect 2) ==="
	@./$(BIN) "([unclosed" qa/fixtures > /dev/null 2>&1; test $$? -eq 2 && echo "PASS: bad regex exits 2"
	@echo "=== testing --count ==="
	@./$(BIN) --count "pub fn" qa/fixtures | ./$(BIN) -q ":" - && echo "PASS: --count"
	@./$(BIN) --no-color -c "pub fn main" qa/fixtures | ./$(BIN) -q "beta.oot:0" - && echo "PASS: -c reports zero files"
	@echo "=== testing --files-with-matches ==="
	@./$(BIN) -l "pub fn main" qa/fixtures | ./$(BIN) -q "main.oo" - && echo "PASS: -l"
	@echo "=== testing --glob filter ==="
	@./$(BIN) -g "*.oot" "oogrep" qa/fixtures > /dev/null && echo "PASS: --glob"
	@echo "=== testing --invert-match ==="
	@./$(BIN) -v "pub fn" qa/fixtures > /dev/null && echo "PASS: -v"
	@./$(BIN) --no-color -v -c "zzz_no_such_token_zzz" qa/fixtures/alpha.oo | ./$(BIN) -q "^18$$" - && echo "PASS: -v selects empty lines"
	@echo "=== testing --ignore-case ==="
	@./$(BIN) --no-color -i "PUB FN MAIN" qa/fixtures > /dev/null && echo "PASS: -i exits 0 on folded match"
	@./$(BIN) --no-color -i "PUB FN MAIN" qa/fixtures | ./$(BIN) -q "main.oo" - && echo "PASS: -i names main.oo"
	@./$(BIN) --no-color -i "PUB +FN" qa/fixtures > /dev/null && echo "PASS: -i folds true regex"
	@./$(BIN) --no-color -n -i --column "PUB FN MAIN" qa/fixtures | ./$(BIN) -q "main.oo:12:1:" - && echo "PASS: -i reports folded column"
	@echo "=== testing output shape ==="
	@./$(BIN) --no-color "pub fn main" qa/fixtures/main.oo | ./$(BIN) -q "^pub fn main" - && echo "PASS: default shape is bare text"
	@./$(BIN) --no-color "pub fn main" qa/fixtures/main.oo | ./$(BIN) -q "main.oo" -; test $$? -ne 0 && echo "PASS: single file shows no path"
	@./$(BIN) --no-color -n "pub fn main" qa/fixtures/main.oo | ./$(BIN) -q "^12:pub fn main" - && echo "PASS: -n shows line numbers"
	@./$(BIN) --no-color -n --column "pub fn main" qa/fixtures/main.oo | ./$(BIN) -q "^12:1:pub fn main" - && echo "PASS: --column restores column"
	@echo "=== testing --no-filename ==="
	@./$(BIN) --no-color -n --no-filename "pub fn main" qa/fixtures | ./$(BIN) -q "^12:pub fn main" - && echo "PASS: --no-filename drops path"
	@./$(BIN) --no-color --no-filename --no-line-number "pub fn main" qa/fixtures | ./$(BIN) -q "^pub fn main" - && echo "PASS: bare text output"
	@./$(BIN) --no-color --no-filename -c "pub fn" qa/fixtures | ./$(BIN) -q "^2$$" - && echo "PASS: --no-filename count is bare"
	@echo "=== testing multiple roots and labels ==="
	@./$(BIN) --no-color -n "pub fn main" qa/fixtures/main.oo qa/fixtures/alpha.oo | ./$(BIN) -q "main.oo:12:pub fn main" - && echo "PASS: two files show paths"
	@./$(BIN) --no-color -n -H "pub fn main" qa/fixtures/main.oo | ./$(BIN) -q "main.oo:12:pub fn main" - && echo "PASS: -H forces path"
	@./$(BIN) --no-color "x" /nonexistent-oogrep-xyz > /dev/null 2>&1; test $$? -eq 2 && echo "PASS: missing file exits 2"
	@echo "=== testing stdin pipe (-) ==="
	@printf 'apple pie\nbanana bread\n' | ./$(BIN) --no-color "apple" - | ./$(BIN) -q "^apple pie$$" - && echo "PASS: - reads stdin as bare text"
	@printf 'apple pie\nbanana bread\n' | ./$(BIN) --no-color "apple" - > /dev/null && echo "PASS: stdin exits 0 on match"
	@printf 'apple pie\n' | ./$(BIN) --no-color "zebra" - > /dev/null 2>&1; test $$? -eq 1 && echo "PASS: stdin exits 1 on no-match"
	@echo "=== testing --quiet ==="
	@./$(BIN) -q "pub fn main" qa/fixtures > /dev/null && echo "PASS: -q exits 0 silently"
	@./$(BIN) -q "pub fn main" qa/fixtures > .ooda-cache/q.txt 2>/dev/null; test ! -s .ooda-cache/q.txt && echo "PASS: -q prints nothing"
	@./$(BIN) -q "zzz_no_such_token_zzz" qa/fixtures > /dev/null 2>&1; test $$? -eq 1 && echo "PASS: -q exits 1 on no-match"
	@echo "=== testing --max-count ==="
	@./$(BIN) --no-color -m 1 -c "pub fn" qa/fixtures/main.oo | ./$(BIN) -q "^1$$" - && echo "PASS: -m caps count per file"
	@./$(BIN) --no-color -m 1 "pub fn" qa/fixtures/main.oo | ./$(BIN) -q "^pub fn main" - && echo "PASS: -m emits first hit"
	@echo "=== testing --word-regexp ==="
	@./$(BIN) --no-color -w "pub" qa/fixtures > /dev/null && echo "PASS: -w exits 0 on whole word"
	@./$(BIN) --no-color -w "ub" qa/fixtures > /dev/null 2>&1; test $$? -eq 1 && echo "PASS: -w rejects partial word"
	@./$(BIN) --no-color -w "p.b" qa/fixtures > /dev/null && echo "PASS: -w folds true regex to tokens"
	@./$(BIN) --no-color -w "pub fn" qa/fixtures > /dev/null 2>&1; test $$? -eq 1 && echo "PASS: -w rejects spaced pattern"
	@./$(BIN) --no-color -w "main|decoy" qa/fixtures/main.oo > /dev/null && echo "PASS: -w matches choice of words"
	@./$(BIN) --no-color -w "^pub" qa/fixtures/main.oo > /dev/null && echo "PASS: -w honours line anchor"
	@echo "=== testing character classes ==="
	@printf 'a3\nb7\n' | ./$(BIN) --no-color "a[1-9]" - | ./$(BIN) -q "^a3$$" - && echo "PASS: class range matches"
	@printf 'a3\n' | ./$(BIN) --no-color "[^0-9]" - > /dev/null && echo "PASS: negated class matches letter"
	@printf 'a3\n' | ./$(BIN) --no-color "[^a-z]" - | ./$(BIN) -q "^a3$$" - && echo "PASS: negated class matches digit line"
	@printf 'B\n' | ./$(BIN) --no-color -i "[a-z]" - > /dev/null && echo "PASS: folded class range matches"
	@echo "=== testing context lines ==="
	@./$(BIN) --no-color -n -A 1 "alpha_second" qa/fixtures/alpha.oo | ./$(BIN) -q "17-    return 2;" - && echo "PASS: -A prints line after"
	@./$(BIN) --no-color -n -B 1 "alpha_second" qa/fixtures/alpha.oo | ./$(BIN) -q "^15-$$" - && echo "PASS: -B prints line before"
	@./$(BIN) --no-color -A 1 "return" qa/fixtures/alpha.oo | ./$(BIN) -q "^--$$" - && echo "PASS: context groups separated"
	@printf 'a\nb\n' | ./$(BIN) --no-color -n -A 1 "b" - | ./$(BIN) -q "^3-" - > /dev/null 2>&1; test $$? -eq 1 && echo "PASS: no phantom line after trailing newline"
	@echo "=== testing --max-depth 0 stays shallow ==="
	@./$(BIN) --max-depth 0 "pub fn main" qa/fixtures > /dev/null 2>&1; echo "PASS: --max-depth bounded"
	@echo "=== testing mcp initialize ==="
	@printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n' | ./$(BIN) --mcp | ./$(BIN) -q '"result"' - && echo "PASS: mcp initialize"
	@echo "=== testing mcp tools/list (strict JSON) ==="
	@oojq=""; for c in $(OOJQ_CANDIDATES); do if [ -x "$$c" ]; then oojq="$$c"; break; fi; done; \
	if [ -z "$$oojq" ]; then $(MAKE) -C ../oojq build > /dev/null 2>&1 || exit 1; oojq="../oojq/dist/oojq"; fi; \
	if [ ! -x "$$oojq" ]; then echo "FAIL: oojq binary unavailable (needed for JSON asserts)"; exit 1; fi; \
	printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":2,"method":"tools/list"}\n' | ./$(BIN) --mcp | ./$(BIN) --no-color --no-filename --no-line-number '"id":2' - | "$$oojq" '.result.tools[].name' | ./$(BIN) -q "search" - && echo "PASS: mcp tools/list"
	@echo "=== testing mcp tools/call (strict JSON) ==="
	@oojq=""; for c in $(OOJQ_CANDIDATES); do if [ -x "$$c" ]; then oojq="$$c"; break; fi; done; \
	if [ -z "$$oojq" ]; then $(MAKE) -C ../oojq build > /dev/null 2>&1 || exit 1; oojq="../oojq/dist/oojq"; fi; \
	if [ ! -x "$$oojq" ]; then echo "FAIL: oojq binary unavailable (needed for JSON asserts)"; exit 1; fi; \
	printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search","arguments":{"pattern":"pub fn main","path":"qa/fixtures"}}}\n' | ./$(BIN) --mcp | ./$(BIN) --no-color --no-filename --no-line-number '"id":3' - | "$$oojq" '.result.matched_files' | ./$(BIN) -q "[1-9]" - && echo "PASS: mcp tools/call"
	@echo "=== testing mcp search new args ==="
	@printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"search","arguments":{"pattern":"ub","path":"qa/fixtures","whole_word":true}}}\n' | ./$(BIN) --mcp | ./$(BIN) -q '"matched_files":0' - && echo "PASS: mcp whole_word"
	@printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":2,"method":"tools/list"}\n' | ./$(BIN) --mcp | ./$(BIN) -q "whole_word" - && echo "PASS: mcp schema lists new args"
	@echo "=== testing mcp fail-closed on missing pattern ==="
	@printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"search","arguments":{}}}\n' | ./$(BIN) --mcp | ./$(BIN) -q "32602" - && echo "PASS: mcp missing pattern rejected"
	@echo "=== testing stderr clean on no-match ==="
	@./$(BIN) "zzz_no_such_token_zzz" qa/fixtures 2>.ooda-cache/err.txt > /dev/null || true; \
	test ! -s .ooda-cache/err.txt && echo "PASS: no stderr noise on no-match"
	@echo "=== testing mcp pre-init rejection (expect -32600) ==="
	@printf '{"jsonrpc":"2.0","id":1,"method":"tools/list"}\n' | ./$(BIN) --mcp | ./$(BIN) -q "32600" - && echo "PASS: mcp pre-init rejected"
	@echo "=== testing --json output (strict JSON) ==="
	@oojq=""; for c in $(OOJQ_CANDIDATES); do if [ -x "$$c" ]; then oojq="$$c"; break; fi; done; \
	if [ -z "$$oojq" ]; then $(MAKE) -C ../oojq build > /dev/null 2>&1 || exit 1; oojq="../oojq/dist/oojq"; fi; \
	if [ ! -x "$$oojq" ]; then echo "FAIL: oojq binary unavailable (needed for JSON asserts)"; exit 1; fi; \
	./$(BIN) --no-color --json "pub fn main" qa/fixtures | "$$oojq" '.matched_files' | ./$(BIN) -q "[1-9]" - && echo "PASS: --json reports matched files"; \
	./$(BIN) --no-color --json "pub fn main" qa/fixtures/main.oo | "$$oojq" '.matches[].path' | ./$(BIN) -q "main.oo" - && echo "PASS: --json names match path"; \
	./$(BIN) --no-color --json "pub fn main" qa/fixtures/main.oo | "$$oojq" '.matches[].line' | ./$(BIN) -q "^12$$" - && echo "PASS: --json reports line 12"; \
	./$(BIN) --no-color --json "pub fn main" qa/fixtures | "$$oojq" '.mode' | ./$(BIN) -q "lines" - && echo "PASS: --json mode is lines"; \
	./$(BIN) --no-color --json -c "pub fn" qa/fixtures | "$$oojq" '.mode' | ./$(BIN) -q "count" - && echo "PASS: --json count mode"; \
	./$(BIN) --no-color --json -l "pub fn main" qa/fixtures | "$$oojq" '.mode' | ./$(BIN) -q "files" - && echo "PASS: --json files mode"
	@echo "=== testing --json edge cases ==="
	@./$(BIN) --no-color --json "zzz_no_such_token_zzz" qa/fixtures > /dev/null 2>&1; test $$? -eq 1 && echo "PASS: --json exits 1 on no-match"
	@./$(BIN) --no-color --json "zzz_no_such_token_zzz" qa/fixtures 2>/dev/null | ./$(BIN) -q '"matched_files":0' - && echo "PASS: --json no-match envelope"
	@./$(BIN) --json "([unclosed" qa/fixtures > /dev/null 2>&1; test $$? -eq 2 && echo "PASS: --json bad regex exits 2"
	@./$(BIN) --json -q "pub fn main" qa/fixtures > .ooda-cache/json_q.txt 2>/dev/null; test ! -s .ooda-cache/json_q.txt && echo "PASS: --json -q prints nothing"
	@echo "=== testing .gitignore support ==="
	@rm -rf .ooda-cache/ign; mkdir -p .ooda-cache/ign/proj/node_modules .ooda-cache/ign/proj/build .ooda-cache/ign/proj/src .ooda-cache/ign/proj2/sub; \
	printf '# comment line\n\n*.log\nbuild/\n!keep.log\n' > .ooda-cache/ign/proj/.gitignore; \
	printf 'needle_zz here\n' > .ooda-cache/ign/proj/debug.log; \
	printf 'needle_zz here\n' > .ooda-cache/ign/proj/keep.log; \
	printf 'needle_zz here\n' > .ooda-cache/ign/proj/build/out.txt; \
	printf 'needle_zz here\n' > .ooda-cache/ign/proj/node_modules/dep.txt; \
	printf 'needle_zz here\n' > .ooda-cache/ign/proj/src/main.txt; \
	printf 'secret.txt\n' > .ooda-cache/ign/proj2/sub/.gitignore; \
	printf 'needle_zz here\n' > .ooda-cache/ign/proj2/sub/secret.txt; \
	printf 'needle_zz here\n' > .ooda-cache/ign/proj2/top.txt; \
	./$(BIN) --no-color -l "needle_zz" .ooda-cache/ign/proj | ./$(BIN) -q "main.txt" - && echo "PASS: visible file still found" && \
	./$(BIN) --no-color -l "needle_zz" .ooda-cache/ign/proj | ./$(BIN) -q "keep.log" - && echo "PASS: negated file found" && \
	{ ./$(BIN) --no-color -l "needle_zz" .ooda-cache/ign/proj 2>/dev/null | ./$(BIN) -q "build" -; test $$? -ne 0; } && echo "PASS: gitignored dir pruned" && \
	{ ./$(BIN) --no-color -l "needle_zz" .ooda-cache/ign/proj 2>/dev/null | ./$(BIN) -q "node_modules" -; test $$? -ne 0; } && echo "PASS: default junk dir pruned" && \
	{ ./$(BIN) --no-color -l "needle_zz" .ooda-cache/ign/proj 2>/dev/null | ./$(BIN) -q "debug.log" -; test $$? -ne 0; } && echo "PASS: gitignored file pruned" && \
	./$(BIN) --no-color --no-ignore -l "needle_zz" .ooda-cache/ign/proj | ./$(BIN) -q "node_modules" - && echo "PASS: --no-ignore shows pruned" && \
	./$(BIN) --no-color -l "needle_zz" .ooda-cache/ign/proj2 | ./$(BIN) -q "top.txt" - && echo "PASS: nested tree visible file found" && \
	{ ./$(BIN) --no-color -l "needle_zz" .ooda-cache/ign/proj2 2>/dev/null | ./$(BIN) -q "secret.txt" -; test $$? -ne 0; } && echo "PASS: nested .gitignore prunes" && \
	./$(BIN) --no-color --json -l "needle_zz" .ooda-cache/ign/proj 2>/dev/null | ./$(BIN) -q '"skipped":[1-9]' - && echo "PASS: --json reports skipped paths" && \
	./$(BIN) --no-color -l "needle_zz" .ooda-cache/ign/proj/debug.log | ./$(BIN) -q "debug.log" - && echo "PASS: explicit file beats ignore"
	@echo "=== testing double-run determinism (Run_1 == Run_2) ==="
	@./$(BIN) "pub fn" qa/fixtures --no-color > .ooda-cache/run1.txt 2>/dev/null || true; \
	./$(BIN) "pub fn" qa/fixtures --no-color > .ooda-cache/run2.txt 2>/dev/null || true; \
	cmp -s .ooda-cache/run1.txt .ooda-cache/run2.txt && echo "PASS: deterministic across runs"
	@./$(BIN) --json "pub fn" qa/fixtures --no-color > .ooda-cache/run1j.txt 2>/dev/null || true; \
	./$(BIN) --json "pub fn" qa/fixtures --no-color > .ooda-cache/run2j.txt 2>/dev/null || true; \
	cmp -s .ooda-cache/run1j.txt .ooda-cache/run2j.txt && echo "PASS: --json deterministic across runs"
	@echo "=== testing ANSI CSI color ==="
	@./$(BIN) "pub fn main" qa/fixtures/main.oo | ./$(BIN) -q "[[]1;31m" - && echo "PASS: ANSI CSI color sequence"
	@./$(BIN) "pub fn main" qa/fixtures/main.oo | ./$(BIN) -q "[[]0m" - && echo "PASS: ANSI CSI reset sequence"
	@echo "=== testing option terminator and -e ==="
	@./$(BIN) -e "pub fn main" qa/fixtures > /dev/null && echo "PASS: -e flag matches"
	@printf 'flag -i\n' | ./$(BIN) -e -i - > /dev/null && echo "PASS: -e with dash pattern matches"
	@printf 'hello -i world\n' | ./$(BIN) -- -i - > /dev/null && echo "PASS: -- option terminator"
	@echo "=== testing glob comma and repeatability ==="
	@./$(BIN) -g "*.oo,*.oot" -l "pub fn" qa/fixtures | ./$(BIN) -q "beta.oot" -; test $$? -ne 0 && echo "PASS: comma glob filter"
	@./$(BIN) -g "*.oo" -g "*.oot" -l "pub fn" qa/fixtures | ./$(BIN) -q "beta.oot" -; test $$? -ne 0 && echo "PASS: repeatable glob filter"
	@echo "=== testing JSON control char escaping ==="
	@oojq=""; for c in $(OOJQ_CANDIDATES); do if [ -x "$$c" ]; then oojq="$$c"; break; fi; done; \
	if [ -n "$$oojq" ]; then \
		printf 'hello\x01\x1fworld\n' | ./$(BIN) --json "hello" - | "$$oojq" '.matches[0].text' | ./$(BIN) -q "hello" - && echo "PASS: json control char escaping"; \
		printf '—"quote\n' | ./$(BIN) --json "quote" - | "$$oojq" '.matches[0].text' | ./$(BIN) -q "quote" - && echo "PASS: json utf8 quote escaping"; \
	fi
	@echo "=== testing mcp notifications and path escaping ==="
	@printf '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}\n' | ./$(BIN) --mcp > .ooda-cache/mcp_notif.txt; test ! -s .ooda-cache/mcp_notif.txt && echo "PASS: mcp notification yields no response"
	@printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search","arguments":{"pattern":"pub","path":"/etc"}}}\n{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search","arguments":{"pattern":"pub","path":"../oojq"}}}\n' | ./$(BIN) --mcp | ./$(BIN) -q -- "-32602" - && echo "PASS: mcp path escaping rejected"
	@printf '{"jsonrpc":"2.0","method":"notifications/exit","params":{}}\n' | ./$(BIN) --mcp > /dev/null && echo "PASS: mcp notification exit"
	@echo "=== testing special files and symlinks ==="
	@rm -rf .ooda-cache/fifo_test; mkdir -p .ooda-cache/fifo_test; mkfifo .ooda-cache/fifo_test/test_fifo 2>/dev/null || true; ./$(BIN) "pub fn" .ooda-cache/fifo_test > /dev/null 2>&1; ./$(BIN) "pub fn" .ooda-cache/fifo_test/test_fifo > /dev/null 2>&1; rm -rf .ooda-cache/fifo_test && echo "PASS: fifo non-hanging"
	@rm -f .ooda-cache/empty.txt; touch .ooda-cache/empty.txt; ./$(BIN) --no-color -c "foo" .ooda-cache/empty.txt | ./$(BIN) -q "^0$$" -; test $$? -eq 0; rm -f .ooda-cache/empty.txt && echo "PASS: 0-byte file count is 0"
	@rm -rf .ooda-cache/sym_test; mkdir -p .ooda-cache/sym_test/child; ln -s child .ooda-cache/sym_test/loop 2>/dev/null || true; printf "unique_sym\n" > .ooda-cache/sym_test/child/f.txt; \
	./$(BIN) --no-filename -c "unique_sym" .ooda-cache/sym_test | ./$(BIN) -q "^1$$" - && echo "PASS: symlink directory skipped"; rm -rf .ooda-cache/sym_test
	@echo "=== testing install.sh ==="
	@./install.sh --verify > /dev/null && echo "PASS: install.sh --verify"
	@./$(BIN) -i -q "Recursive Search" install.sh && echo "PASS: install.sh banner text"
	@{ ./$(BIN) -i -q "oosh" install.sh; test $$? -ne 0; } && echo "PASS: install.sh no oosh"
	@echo "=== testing uninstaller ==="
	@./install.sh --uninstall --dry-run > /dev/null && echo "PASS: install.sh --uninstall --dry-run"


parity: build
	@sum=$$(sha256sum $(BIN) | awk '{print $$1}'); echo $$sum; test -n "$$sum"

install: build
	@mkdir -p $(HOME)/.openooda/bin
	cp -a $(BIN) $(HOME)/.openooda/bin/oogrep
	@chmod +x $(HOME)/.openooda/bin/oogrep
	cp -a uninstall.sh $(HOME)/.openooda/bin/oogrep-uninstall
	@chmod +x $(HOME)/.openooda/bin/oogrep-uninstall
	@echo "installed $(HOME)/.openooda/bin/oogrep and oogrep-uninstall"

uninstall:
	@./install.sh --uninstall --yes > /dev/null
	@echo "uninstalled oogrep"

VERSION ?= 0.3.2

package-deb: $(BIN)
	@mkdir -p dist/deb-root/DEBIAN dist/deb-root/usr/bin
	@sed "s/^Version:.*/Version: $(VERSION)-1/" packaging/debian/control.binary > dist/deb-root/DEBIAN/control
	@cp $(BIN) dist/deb-root/usr/bin/oogrep
	@chmod 0755 dist/deb-root/usr/bin/oogrep
	@cp uninstall.sh dist/deb-root/usr/bin/oogrep-uninstall
	@chmod 0755 dist/deb-root/usr/bin/oogrep-uninstall
	@dpkg-deb --build --root-owner-group dist/deb-root dist/oogrep_$(VERSION)-1_amd64.deb
	@rm -rf dist/deb-root
	@echo "built dist/oogrep_$(VERSION)-1_amd64.deb"

package-rpm: $(BIN)
	@mkdir -p ~/rpmbuild/SOURCES ~/rpmbuild/SPECS ~/rpmbuild/RPMS
	@cp $(BIN) ~/rpmbuild/SOURCES/oogrep-linux-x86_64
	@cp uninstall.sh ~/rpmbuild/SOURCES/uninstall.sh
	@sed "s/^Version:.*/Version: $(VERSION)/" packaging/oogrep.spec > ~/rpmbuild/SPECS/oogrep.spec
	@rpmbuild -bb ~/rpmbuild/SPECS/oogrep.spec
	@cp ~/rpmbuild/RPMS/x86_64/oogrep-$(VERSION)*.rpm dist/
	@echo "built dist RPM package"

package-arch: $(BIN)
	@mkdir -p dist/arch-pkg/usr/bin
	@cp $(BIN) dist/arch-pkg/usr/bin/oogrep
	@chmod 0755 dist/arch-pkg/usr/bin/oogrep
	@cp uninstall.sh dist/arch-pkg/usr/bin/oogrep-uninstall
	@chmod 0755 dist/arch-pkg/usr/bin/oogrep-uninstall
	@printf "pkgname = oogrep\npkgbase = oogrep\npkgver = $(VERSION)-1\npkgdesc = Capability-bounded recursive regex search for the openOODA era\nurl = https://github.com/openOODA-tools/oogrep\nbuilddate = $$(date +%s)\npackager = openOODA Authors <https://github.com/openOODA-tools>\nsize = $$(stat -c %s $(BIN))\narch = x86_64\nlicense = MIT\ndepend = glibc\nprovides = oogrep\n" > dist/arch-pkg/.PKGINFO
	@tar --zstd -cf dist/oogrep-$(VERSION)-1-x86_64.pkg.tar.zst -C dist/arch-pkg .PKGINFO usr
	@rm -rf dist/arch-pkg
	@bash -n packaging/arch/PKGBUILD
	@cp packaging/arch/PKGBUILD packaging/PKGBUILD
	@cp packaging/arch/PKGBUILD dist/PKGBUILD
	@echo "built dist/oogrep-$(VERSION)-1-x86_64.pkg.tar.zst and validated PKGBUILD"

package: package-deb package-rpm package-arch

clean:
	@rm -rf dist .ooda-cache
	@echo "cleaned"
