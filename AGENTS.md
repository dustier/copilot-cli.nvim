# AGENTS.md

This file provides guidance to Qoder (qoder.com) when working with code in this repository.

## Project Overview

copilot-cli.nvim is a Neovim plugin (pure Lua, no build dependencies) that bridges Neovim with running CLI tools (GitHub Copilot CLI and qodercli) via tmux. Users compose prompts in a floating editor with smart placeholders (`@file`, `@buffers`, `@here`, `@selection`, `@diagnostics`) that expand to compact references, then the plugin delivers the prompt to a CLI tool's tmux pane using bracketed-paste (`load-buffer` + `paste-buffer`).

## Build, Test, and Lint

There is no build system, linter, or automated test suite.

Smoke test (headless):
```bash
nvim --headless -u NONE \
  '+set runtimepath+='$(pwd) \
  '+lua require("copilot-cli").setup()' \
  '+qa!'
```

Targeted module checks (inside Neovim):
```vim
:lua require("copilot-cli.detect").find_targets()
:lua require("copilot-cli.detect").find_cli_processes()
:lua require("copilot-cli.context").replace_placeholders("Explain @here in @file")
:lua require("copilot-cli.send").send("%36", "test")
```

## Architecture

Runtime flow: **user command -> prompt editor -> placeholder expansion -> target detection/cache -> tmux paste**.

- **`plugin/copilot-cli.lua`** -- Entrypoint. Registers `:AISend` and `:AISelect` commands, delegates to `lua/copilot-cli/init.lua`.

- **`lua/copilot-cli/init.lua`** -- Orchestration and prompt UI. Opens a scratch floating buffer near the cursor that grows dynamically (up to 10 lines). Normal-mode `<CR>` / `<C-s>` submit; insert-mode `<CR>` is a newline. Visual mode prefills `@selection `. Calls `detect.get_target()` then `send.send()` on submission.

- **`lua/copilot-cli/context.lua`** -- Placeholder expansion. Placeholders expand to **compact `@`-prefixed references** (paths, line numbers, line ranges), never to file contents. `get_cursor()` resolves through floating windows to the underlying editing window so `@here`/`@diagnostics` reference the file being edited, not the prompt buffer.

- **`lua/copilot-cli/detect.lua`** -- Process detection. Defines a `cli_tools` table listing supported tools (copilot, qodercli) with their regex, basename, and exclusion patterns. Scans `ps` output, builds a process tree, lists all tmux panes, then uses BFS to match CLI descendants to pane root PIDs. Each target carries a `tool` field. Caches the selected target; liveness checks re-scan the cached pane and refresh the PID if the process restarted. The `ps` command has a `$USER` -> `whoami` -> `ps -e` fallback chain.

- **`lua/copilot-cli/send.lua`** -- Transport. Wraps text in bracketed-paste escape sequences (`\027[200~...\027[201~`), pipes to `tmux load-buffer -`, then runs `tmux paste-buffer -t <pane_id>`.

## Key Conventions

- Use `vim.system()` with argv tables (not shell strings) for all subprocess calls.
- Use `vim.notify()` with `vim.log.levels.*` for user-facing messages.
- Escape `%` in replacement text before calling `string.gsub` to avoid pattern substitution bugs.
- Copilot process detection must match only executables whose basename is exactly `copilot` and must exclude `language-server`, `nvim`, `vim`, and `node` processes. Qodercli detection matches basename `qodercli`. New tools are added to the `cli_tools` table in `detect.lua`.
- Placeholder outputs are always `@`-prefixed references relative to cwd or home-shortened; `@selection` returns a file line range, not selected text.
- The prompt float is a scratch `nofile` buffer; resolve placeholders through the previous window (`winnr("#")`), and clear `showbreak` to avoid obscuring wrapped text.
- All modules use the `local M = {} ... return M` pattern with LuaCATS annotations (`---@param`, `---@return`) on public functions.
