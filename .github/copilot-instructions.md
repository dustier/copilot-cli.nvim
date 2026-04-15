# Copilot Instructions for copilot-cli.nvim

## Build, Test, and Lint Commands

There is no build system, linter, or automated test suite. Validation is done by loading the plugin in Neovim and probing modules directly.

Full plugin smoke test:

```bash
nvim --headless -u NONE \
  '+set runtimepath+=/absolute/path/to/copilot-cli.nvim' \
  '+lua require("copilot-cli").setup()' \
  '+qa!'
```

Interactive load in a real Neovim session:

```vim
:set runtimepath+=/absolute/path/to/copilot-cli.nvim
:lua require("copilot-cli").setup()
```

Targeted module checks:

```vim
:lua require("copilot-cli.detect").find_targets()
:lua require("copilot-cli.detect").find_cli_processes()
:lua require("copilot-cli.context").replace_placeholders("Explain @here in @file")
:lua require("copilot-cli.send").send("%36", "test")
```

## High-Level Architecture

The runtime flow is: **user command → prompt editor → placeholder expansion → target detection/cache → tmux paste**.

1. `plugin/copilot-cli.lua` is the entrypoint that registers the `:AISend` and `:AISelect` commands and delegates everything else to `lua/copilot-cli/init.lua`.

2. `init.lua` owns the prompt UI and orchestration. `AISend` opens a scratch floating buffer near the cursor, starts at one line, grows with content, keeps insert-mode `<CR>` as newline, and maps normal-mode `<CR>` / `<C-s>` to submission. Visual mode preloads `@selection ` before opening the prompt.

3. `context.lua` turns prompt placeholders into references derived from the current editing state. The placeholders intentionally expand to compact references such as `@path/to/file`, `@path/to/file:42`, or `@path/to/file:10-20` rather than file contents. `get_cursor()` specifically resolves through floating windows back to the underlying editing window so prompt floats do not break `@here` or diagnostics lookup.

4. `detect.lua` is responsible for finding supported CLI tool instances (copilot and qodercli) anywhere in tmux, not just the current window. It defines a `cli_tools` table listing each tool's name, regex, expected basename, and exclusion patterns. It scans `ps`, filters against all tool patterns, builds a process tree, lists tmux panes, and matches CLI descendants to pane root PIDs. Each target carries a `tool` field identifying which CLI it is. The cache is keyed by the selected pane in practice: liveness checks rebuild matches for the cached `pane_id` and refresh the cached PID if that pane still hosts a CLI descendant.

5. `send.lua` is the transport layer. Messages are sent to tmux with `load-buffer` + `paste-buffer`, wrapped in bracketed-paste escapes because CLI tools ignore plain `send-keys` style input.

## Key Conventions

- Prefer `vim.system()` with argv tables over shell strings for subprocess work.
- User-facing failures and status updates should go through `vim.notify()` with `vim.log.levels.*`.
- Placeholder replacements must escape `%` before `gsub`, or replacement text can be interpreted as a pattern substitution.
- Placeholder outputs are always `@`-prefixed references relative to the current working directory or home-shorted path; `@selection` returns a file line range, not the selected text itself.
- Copilot process detection should only treat an executable whose basename is exactly `copilot` as a match, and qodercli detection should match basename `qodercli`. Both must continue excluding `nvim`, `vim`, and `node` processes. Copilot additionally excludes `language-server` processes. New CLI tools are added to the `cli_tools` table in `detect.lua`.
- The process scan must keep the `$USER` → `whoami` → `ps -e` fallback in `ps_cmd()` because some environments do not populate `$USER`.
- The prompt UI is a scratch `nofile` floating buffer, so changes there should preserve float-specific behavior such as resolving placeholders through the previous window and clearing `showbreak` to avoid wrapped text being obscured.
- Public module APIs follow the local `M` module pattern and use LuaCATS annotations (`---@param`, `---@return`) on callable functions.
