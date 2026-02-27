# Copilot Instructions for copilot-cli.nvim

## Build & Test

No build system or test suite. This is a pure Neovim Lua plugin — test by loading in Neovim:

```vim
:set runtimepath+=path/to/copilot-cli.nvim
:lua require("copilot-cli").setup()
```

Test individual modules in isolation:

```vim
:lua require('copilot-cli.detect').find_targets()
:lua require('copilot-cli.send').send('%36', 'test')
```

## Architecture

Three-stage pipeline: **detect → send → context**.

1. **detect.lua** — Finds running `copilot` processes via `ps`, builds a process tree, then maps copilot PIDs to tmux panes by walking from each pane's root PID downward. Results cached in `M._target`, invalidated via `nvim_get_proc()`. The `ps_cmd()` helper falls back from `$USER` → `whoami` → `ps -e` for environments where `$USER` is unset.

2. **send.lua** — Sends text via `tmux load-buffer` (with stdin) + `paste-buffer`. Text is wrapped in **bracketed paste** escape sequences (`\027[200~...\027[201~`) because copilot CLI's TUI only accepts pasted text through this mechanism — plain `send-keys` is silently ignored.

3. **context.lua** — Resolves `@placeholder` tokens (`@file`, `@buffers`, `@here`, `@selection`, `@diagnostics`) in prompts before sending. The `get_cursor()` helper resolves through floating windows to the underlying buffer. Replacement strings are `%`-escaped before `gsub` to prevent pattern interpretation.

4. **init.lua** — Orchestrates the pipeline and owns configuration. `get_target()` uses a callback pattern because `vim.ui.select` is async when multiple copilot instances are found.

## Conventions

- Use `vim.system()` for subprocess execution (structured args, stdin support, no shell escaping needed)
- Use `vim.notify()` with `vim.log.levels.*` for user messages
- Copilot process matching checks executable basename is literally `"copilot"`, excludes `language-server`, `nvim`, `node`
- Commands use `Copilot` prefix: `CopilotSend`, `CopilotSelect`
- Config keys and functions use `snake_case`
- Module pattern: `local M = {}` / `return M`
- Use `---@param` / `---@return` LuaCATS annotations for public functions
