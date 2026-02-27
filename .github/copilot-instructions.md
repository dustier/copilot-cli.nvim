# Copilot Instructions for copilot-cli.nvim

## Build & Test

No build system. This is a pure Neovim Lua plugin — test by loading it in Neovim:

```vim
:set runtimepath+=path/to/copilot-cli.nvim
:lua require("copilot-cli").setup()
```

## Architecture

The plugin has a three-stage pipeline: **detect → send → present**.

1. **detect.lua** finds running `copilot` processes using `ps`, then maps them to tmux panes by walking the process tree (pane_pid → children → copilot PID). Detection is decoupled from tmux — only the PID lookup uses `ps`, tmux is only needed for pane mapping. Results are cached in `M._target` and invalidated when the process exits (`nvim_get_proc`).

2. **send.lua** communicates with the target pane via `tmux load-buffer` + `paste-buffer` (not `send-keys`). This two-step approach handles long text, special characters, and multi-line content reliably.

3. **context.lua** resolves `@placeholder` tokens in user prompts before sending. The `get_cursor()` helper resolves through floating windows to the underlying buffer — this is important because the prompt UI itself is a floating window.

4. **init.lua** orchestrates the pipeline and owns configuration. `get_target()` uses a callback pattern because `vim.ui.select` is async when multiple copilot instances are found.

## Conventions

- Use `vim.system()` for all shell commands (not `io.popen` or `vim.fn.system`)
- Use `vim.notify()` with `vim.log.levels.*` for user messages
- Copilot process matching uses `vim.regex("\\<copilot\\>")` and excludes `language-server` to avoid matching Copilot LSP
- Commands use `Copilot` prefix in PascalCase: `CopilotSend`, `CopilotPrompt`, `CopilotSelect`
- Config keys and functions use `snake_case`
- Module pattern: `local M = {}` at top, `return M` at bottom
- 2-space indentation
- Use `---@param` / `---@return` LuaCATS annotations for public functions
