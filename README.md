# oogrep

> **Capability-bounded recursive regex search for the openOODA era.**  
> *A drop-in `grep`/`ripgrep` replacement written in openOODA, with a first-class MCP surface for agent callers.*

Part of [openOODA-tools](https://github.com/openOODA-tools).

---

## 1. Installation

`oogrep` has zero runtime dependencies. It compiles to a standalone native binary linked directly with the host libc.

### Universal Web Installer
Installs the standalone native binary to `/usr/local/bin` (or `~/.local/bin`) with automatic SHA-256 seal verification:

```bash
curl -fsSL https://openooda-tools.github.io/oogrep/install.sh | bash
```

### Native Packages (APT & DNF)
Prebuilt packages are attached to every [GitHub Release](https://github.com/openOODA-tools/oogrep/releases):

```bash
# Debian, Ubuntu (APT)
sudo apt install ./oogrep_0.3.0-1_amd64.deb

# Fedora, RHEL, Rocky, Alma (DNF)
sudo dnf install ./oogrep-0.3.0-1.*.rpm
```

Or install with package manager flags via the installer:
```bash
# Debian / Ubuntu (APT)
curl -fsSL https://openooda-tools.github.io/oogrep/install.sh | bash -s -- --apt

# Fedora / RHEL (DNF)
curl -fsSL https://openooda-tools.github.io/oogrep/install.sh | bash -s -- --dnf
```

### Options
```bash
# Preview actions without modifying the host
curl -fsSL https://openooda-tools.github.io/oogrep/install.sh | bash -s -- --dry-run

# Verify cryptographic SHA-256 seal only
curl -fsSL https://openooda-tools.github.io/oogrep/install.sh | bash -s -- --verify

# Uninstall (removes binary or package)
curl -fsSL https://openooda-tools.github.io/oogrep/install.sh | bash -s -- --uninstall
```

---

## 2. Two Faces, One Search

`oogrep` is a filter and an agent tool at the same time. Both surfaces call the same pages in `walk/`, `match/`, and `render/`.

| Surface | Invocation | Audience |
| :--- | :--- | :--- |
| **CLI** | `oogrep <pattern> [path]` | humans, pipes, scripts |
| **MCP** | `oogrep --mcp` | LLM agents over stdio |

The MCP surface speaks JSON-RPC over stdin/stdout. No socket, no port, no daemon. Any MCP client can spawn it directly.

---

## 3. Usage

```
oogrep [flags] <pattern> [path]

flags:
  -e, --regexp <pattern>   use pattern for matching
  -g, --glob <pattern>     include files matching glob (repeatable via comma)
  -i, --ignore-case        case-insensitive matching
  -v, --invert-match       select non-matching lines
  -c, --count              print per-file match counts instead of lines
  -l, --files-with-matches print only paths that matched
  -n, --line-number        print line numbers (default off)
  -H, --with-filename      always print the path prefix
      --no-line-number     suppress line numbers
      --no-color           disable ANSI color
      --column             print the match column (default off)
      --no-filename        suppress the path prefix
      --json               emit one machine-readable JSON object
  -q, --quiet              suppress output, exit code only
  -m, --max-count <n>      stop after n matching lines per file
  -w, --word-regexp        match whole words only
  -A, --after-context <n>  print n lines after each match
  -B, --before-context <n> print n lines before each match
  -C, --context <n>        print n lines around each match
      --max-depth <n>      limit traversal depth (default 32)
      --max-matches <n>    cap emitted matches, report any suppressed count
      --no-ignore          do not skip ignored paths (.gitignore + defaults)
  -h, --help               display help
  -V, --version            display version
      --mcp                run the MCP stdio server
```

### Exit Codes

| Code | Meaning |
| :--- | :--- |
| `0` | at least one match found |
| `1` | search completed, no match |
| `2` | usage or I/O error |

This is the `grep` convention. `oogrep` is safe in a pipeline and in `set -e` scripts.

### Column Reporting

By default `oogrep` reports `path:line:text`, exactly like `grep`, so scripts
that parse `grep` output keep working. Pass `--column` to add the match column
(`path:line:column:text`). The column is reported when the pattern is a
**literal** string with no regex metacharacters. For a pattern that uses regex
metacharacters, the column is omitted rather than guessed:

```
oogrep "pub fn" main.oo                 # pub fn main() ...
oogrep -n "pub fn" main.oo              # 12:pub fn main() ...
oogrep -n --column "pub fn" main.oo     # 12:1:pub fn main() ...
oogrep -n --column "^pub fn" main.oo    # 12:pub fn main() ...
```

Paths print when the search spans inputs (a directory tree or several roots),
never for one file or one pipe — the `grep` label rule. `-H` forces paths on,
`--no-filename` forces them off.

The runtime regex engine reports a correct match/no-match answer and a correct end
offset, but its start offset reads zero and its matched text yields only the final
character of the match. Rather than print a wrong column, `oogrep` locates literal
matches exactly and declines to claim a column for general regex patterns.

### JSON Output

`grep` prints text only, so scripts must scrape it. `oogrep --json` prints one
stable object instead — every field always present, display flags ignored:

```
oogrep --json "pub fn main" src/
```

```json
{
  "tool": "oogrep",
  "version": "0.3.0",
  "pattern": "pub fn main",
  "mode": "lines",
  "matches": [
    {"path": "src/main.oo", "line": 12, "column": 1, "length": 11, "context": false, "text": "pub fn main() ..."}
  ],
  "counts": [],
  "files": [],
  "files_scanned": 4,
  "matched_files": 1,
  "total_matches": 1,
  "dropped": 0,
  "truncated": false
}
```

`mode` follows the summary flags: `lines` by default, `count` with `-c`
(`counts` filled), `files` with `-l` (`files` filled). A no-match search still
exits `1` with empty arrays; a bad pattern still exits `2`. `column` reads `0`
when the pattern is a general regex, for the reason above. `skipped` counts
paths pruned by the ignore policy below.

### Ignored Paths

`grep` searches everything, including dependency folders and build output.
`oogrep` skips the junk by default:

- Built-in prune list: `.git`, `target`, `dist`, `node_modules`,
  `.ooda-cache`, `.venv`, `__pycache__`, `.cache`.
- Every `.gitignore` found while walking, at any depth: `*`, `?`,
  `!` negation, trailing `/` for directories, leading `/` anchoring.
  No `[...]` classes, no backslash escapes.
- A file named directly on the command line is always searched.
  Naming a file is intent.

`--no-ignore` turns all of it off. `--json` reports pruned paths as `skipped`.

### grep vs oogrep Scoreboard

Same tasks, both tools, same machine. Last verified on release day
(see the GitHub release notes for the run):

| Check | `grep` | `oogrep` |
| :--- | :--- | :--- |
| Everyday search output (48 side-by-side cases) | — | byte-identical, 48/48 |
| Committed self-checks (`make all`) | — | all green |
| Exit codes (`0` match, `1` none, `2` error) | yes | yes |
| Machine-readable JSON (`--json`) | no | yes |
| Agent hookup (MCP stdio) | no | yes |
| Skips `.gitignore` + junk folders | no | yes |
| 500-file project search | instant | instant (under 0.02 s) |

Honest limits: the match column reads `0` for general regex patterns,
and `.gitignore` covers the common subset above. Anything else that
differs from `grep` is a bug — report it.

### Examples

```bash
# Recursive search with line numbers
oogrep -n "pub fn main" src/

# Only .oo files, case-insensitive
oogrep -i -g "*.oo" "capability" .

# Which files mention a token, no line detail
oogrep -l "FsReadCap" ~/Projects

# Count matches per file
oogrep -c "let mut" src/

# Invert: find lines without a trailing newline marker
oogrep -v "^\s*//" main.oo
```

---

## 4. Agent Usage (MCP)

Configure any MCP client to launch the binary:

```json
{
  "mcpServers": {
    "oogrep": {
      "command": "oogrep",
      "args": ["--mcp"]
    }
  }
}
```

The server exposes a `search` tool. Arguments:

| Field | Type | Default | Meaning |
| :--- | :--- | :--- | :--- |
| `pattern` | string | *required* | regex to match |
| `path` | string | `"."` | root to search |
| `glob` | string | `""` | include glob |
| `ignore_case` | bool | `false` | case-insensitive |
| `invert` | bool | `false` | select non-matching lines |
| `whole_word` | bool | `false` | match whole words only |
| `max_matches` | int | `0` | stop after this many hits per file, 0 uncapped |
| `context_before` | int | `0` | lines printed before each match |
| `context_after` | int | `0` | lines printed after each match |
| `max_depth` | int | `32` | traversal depth bound |
| `max_chars` | int | `4000` | output cap, clamped to 65536 |

Results are bounded by `max_chars` and marked `...[truncated]` when clipped, because an agent context window is finite.

### Capability Attenuation

`oogrep` holds only `&FsReadCap` and never spawns a process. When exposed to an agent, scope the grant rather than the tool: a read capability narrowed to a `path_prefix` with a request TTL lets an agent search one subtree and nothing else, and the grant expires on its own. See `attenuate_capability` in the openOODA MCP server.

---

## 5. Build From Source

```bash
git clone git@github.com:openOODA-tools/oogrep.git
cd oogrep

# Build, verify, and test
make all

# Install locally
make install
```

`std/` resolves by parent walk to the sibling `openOODA-tools/std` checkout. No symlink is required inside this repository.

---

## 6. Verification & Governance

All code adheres strictly to the openOODA House Laws documented in [`AGENTS.md`](AGENTS.md):
- **Page Rule**: Every source file strictly bounded between 16 and 256 lines, at most 8 per directory.
- **Academy Headers**: Mandatory 4-element ASD-STE100 docstrings on every page.
- **Zero-Panic Invariant**: Robust error propagation without unvetted crashes.
- **Exit Code Law**: `0` match, `1` no match, `2` error — never a failed search returning success.
- **File Law**: Clean tree with no forbidden file extensions or stray docs.
