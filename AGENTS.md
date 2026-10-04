# oogrep: House Laws & Agent Engineering Standards (v1)

This document is the **single canonical source of truth** for all code, architecture, and system integration standards across `oogrep`. Every human contributor and AI agent must strictly follow these rules without exception.

---

## 1. The Page Rule (Code Layout & Sizing)

A **page** is one committed `.oo` or `.oot` file. Every page holds one idea, fits in one head, and carries its own weight. This rule is enforced by automated verification under `make verify`: red pages fail the build.

### Hard Sizing Invariants
- **16–256 Lines**: Every committed source file must be between **16 and 256 lines**, counted as exact line breaks (blank lines and comments count).
- **Shim Exemption (Floor Only)**: A file is a shim when every non-comment line is an import or re-export (`import "..."`). Shims skip the 16-line floor. The **256-line ceiling still strictly applies**.
- **Directory Density ($\le 8$ files)**: At most **8 `.oo` files per directory**, tests included. Crowded directories must split into functional subdirectories grouped by domain.
- **Banned File Names (Name the function, not the drawer)**:
  `util.oo`, `utils.oo`, `helper.oo`, `helpers.oo`, `common.oo`, `misc.oo`, `shared.oo`, `base.oo`, `core.oo`.

### Splitting, Folding, and Naming
- **Over 256 lines**: Split along functional boundaries into a new subdirectory with an `anchor.oo` shim. One page = one verb or one wholly owned noun.
- **Under 16 lines (and not a shim)**: Fold into its closest sibling or caller. Never pad lines with artificial whitespace or comments to reach 16.
- **Action pages lead with a verb**: `collect_candidates.oo`, `compile_pattern.oo`, `render_match.oo`.
- **State pages name what they own**: `search_opts.oo`, `hit.oo`.
- **Boundary pages speak trust verbs**: `compile_pattern.oo`, `admit_candidate.oo`, `enforce_scope.oo`.

### The Three Domains
Pages group into functional subdirectories, never a flat pile:

- **`walk/`** — produce and filter the candidate file set. Owns traversal, glob matching, and file-kind admission. Knows nothing about regexes.
- **`match/`** — turn a candidate path plus a compiled pattern into ranked `Hit` records. Knows nothing about color or terminal state.
- **`render/`** — turn `Hit` records into terminal output. Owns color, summary, and error presentation. Never re-reads the filesystem.
- **`mcp/`** — expose the same search over MCP stdio for agent callers. Thin transport only; it delegates to `walk/`, `match/`, and `render/` and owns no search logic of its own.

A page may not reach across domains to duplicate a neighbour's work. If `render/` needs a field, `match/` provides it on the record.

---

## 2. The 4-Element Academy Header (Mandatory on Every Page)

Every committed `.oo` file must begin with the standard 4-element Academy docstring:

```oo
// # Component Name - Subtitle
//
// Logline: Single-sentence imperative summary of functional responsibility.
//
// Setup: Preconditions, wired capability tokens, imported contracts.
//
// Beats:
//   1. First sequential phase of execution.
//   2. Next phase.
//   3. Final phase / exit state.
```

- **ASD-STE100 Compliance**: Clear, concise English. No filler or ambiguous verbs.
- **Imports**: All imports must be relative string literals (e.g. `import "std/fs/os/fs.oo";`). Never use `::` namespaces.

---

## 3. openOODA Capability & Security Discipline

`oogrep` operates strictly on the Object-Capability (OCap) security model. It is an agent-facing tool, so this section is load-bearing rather than ceremonial.

### Unforgeable Capability Tokens
- **Zero Ambient Authority**: `oogrep` never reads a file without an explicit `&FsReadCap` threaded from `main`. It holds no `&FsWriteCap` and never opens a network socket.
- **Read-Only by Construction**: A search tool has no reason to write or open network. The absence of `&FsWriteCap` and `&NetCap` in `main` is the enforcement, not a convention.
- **The One Process Exception**: `main` declares `&ProcessCap` solely to raise a non-zero exit status, because the runtime does not derive the process status from main's return value and `process_exit` is classified under `ProcessCap`. **`oogrep` never spawns a process.** A page that spawns anything violates this law, and the capability is present only so the exit code law is not traded for a stderr warning on every no-match search.
- **Path Scope**: Every candidate path is admitted under the caller's read scope. The MCP layer must refuse any request whose root escapes the attested `path_prefix` of its attenuated token.

### Subprocess Safety
- **Never invoke `/bin/sh -c` or `/bin/bash -c`**: `oogrep` spawns nothing. This is stricter than the general openOODA rule and is not negotiable — a search tool that shells out has already failed.
- **No `process_exec`**: The `std/fs/process/process.oo` `process_exec` wrapper is a `sh -c` convenience and is banned in this repo. Direct `sys_exec` with an explicit argv array is the only sanctioned form, should a future page need it.

---

## 4. Search Correctness & Exit Code Invariants

`oogrep` is a drop-in filter. Its contract with pipes is sacred.

1. **Exit Code Law**: `0` when at least one match is found, `1` when the search completes with no match, `2` on usage or I/O error. This is the `grep` convention and scripts depend on it. Never return `0` from a failed search.
2. **Binary Admission**: A candidate containing a NUL byte in its first probe window is rejected, not printed. Printing binary garbage into a pipeline corrupts downstream tools.
3. **Line Orientation**: One output record per matching line, never per match. A line matching five times is one line, with the first match located.
4. **Deterministic Order**: Within a file, lines ascend. Across files, the order is the traversal order. A search run twice over an unchanged tree produces byte-identical output.

---

## 5. Agent Surface (MCP stdio)

The MCP server is a first-class surface, not an afterthought.

1. **stdio only**: `oogrep --mcp` speaks JSON-RPC over stdin/stdout. No socket, no port, no daemon, no discovery service.
2. **Bounded Output**: Every tool result truncates at `max_chars`, defaulting to 4000 and clamped to 65536. An agent has a finite context window; a tool that floods it is a broken tool.
3. **Fail Closed**: An unparsable pattern, an out-of-scope path, or an unknown method returns a structured error object. Never an empty success.
4. **Protocol Discipline**: `tools/call` before `initialize` returns `-32600`. Shutdown and exit are terminal.

---

## 6. Verification & QA Gate

Before any commit or release is certified, the entire codebase must pass the automated verification gate:

1. **`make check`**: Full syntax and semantic verification via `oodac check` across every `.oo` page.
2. **`make line-cap`**: Hard verification that 100% of `.oo` and `.oot` files are between 16 and 256 lines, honouring the shim exemption.
3. **`make academy`**: Verification that every source file contains the complete 4-element Academy header in its first 7 lines.
4. **`make density`**: Verification that no directory holds more than 8 pages, tests included.
5. **`make file-law`**: Verification that no forbidden file extensions or stray documents are committed.
6. **`make parity`**: Verification that compiled release binaries match verified hashes.
7. **`make all`**: Full clean build (`dist/oogrep`), double-run test execution ($Run_1 == Run_2$), and zero warnings.
8. **`make pure`**: Audit that committed test steps assert through openOODA-built tools only (the binary itself, oojq). No python, stock grep, or jq in any test step.

All eight run under `make verify`. The header check is strict about position: all four Academy elements must land within the first 7 lines, so a multi-line `Setup:` block pushes `Beats:` out of range and fails the build. Put supplementary notes *below* the `Beats:` block.
