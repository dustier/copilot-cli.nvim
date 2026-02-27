# copilot-cli.nvim

A Neovim plugin that connects Neovim with a running [GitHub Copilot CLI](https://github.com/github/copilot-cli) instance. Send context-rich prompts from your editor directly to Copilot CLI running in another tmux pane.

## Features

- 🔍 **Smart process detection** — Finds running `copilot` instances via process tree traversal (not limited to current tmux window)
- 💬 **Interactive prompt input** with placeholder support
- 📄 `@file` — Current file path (relative)
- 📁 `@buffers` — All open buffer paths
- 📍 `@here` — Cursor position info
- ✂️ `@selection` — Visual selection content
- 🔍 `@diagnostics` — LSP diagnostics for current line
- 🖥️ **Reliable tmux sending** — Uses `load-buffer` + `paste-buffer` (handles long text and special characters)
- ⚡ **Multi-instance support** — Detects multiple Copilot CLI instances and lets you choose

## Requirements

- Neovim >= 0.8.0
- `tmux` — Required for sending messages to Copilot CLI
- `copilot` CLI running in a tmux pane (any session/window)

## Installation

### lazy.nvim

```lua
{
  "copilot-cli.nvim",
  dev = true,
  opts = {
    auto_detect = true,
    tmux_target = nil, -- Manual override: tmux pane id (e.g., "%42")
    auto_submit = true, -- Automatically press Enter after sending
  },
  keys = {
    { "<C-l>", "<cmd>CopilotSend<cr>", desc = "Send prompt to Copilot CLI" },
    { "<C-l>", "<cmd>CopilotSend<cr>", mode = "v", desc = "Send selection to Copilot CLI" },
    { "<leader>cs", "<cmd>CopilotSelect<cr>", desc = "Select Copilot CLI instance" },
  },
  cmd = {
    "CopilotSend",
    "CopilotSelect",
  },
  config = function(_, opts)
    require("copilot-cli").setup(opts)
  end,
}
```

### packer.nvim

```lua
use {
  'copilot-cli.nvim',
  config = function()
    require('copilot-cli').setup({
      auto_detect = true,
      tmux_target = nil,
      auto_submit = true,
    })
  end
}
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:CopilotSend` | Open prompt input with placeholder support |
| `:CopilotSelect` | Re-detect and select Copilot CLI instance |

### Placeholders

Use these in your prompts to include context:

| Placeholder | Description |
|-------------|-------------|
| `@file` | Current file path (relative to cwd) |
| `@buffers` | All open buffer file paths |
| `@here` | Cursor position (file, line, column) |
| `@selection` | Visual selection content |
| `@diagnostics` | LSP diagnostics for the current line |

### Example Prompts

- `"Fix this error: @diagnostics"`
- `"Explain this code: @selection"` (select text first)
- `"What does @file do?"`
- `"Add tests for @file"`
- `"Help me at @here in @file"`

### Workflow

1. Start tmux and split your terminal
2. Run `copilot` in one pane
3. Open Neovim in another pane (can be any tmux session/window)
4. Press `<C-l>` to open the prompt input
5. Type your prompt with placeholders and press Enter
6. The prompt is sent to the Copilot CLI pane automatically

## Configuration

```lua
require("copilot-cli").setup({
  auto_detect = true,   -- Auto-detect copilot instances via process tree
  tmux_target = nil,    -- Manual override: tmux pane id (e.g., "%42")
  auto_submit = true,   -- Automatically submit after pasting the prompt
  submit_key = "C-q",   -- Key to submit (C-q for autopilot mode, Enter for interactive)
})
```

## How It Works

### Detection Strategy

Unlike simpler approaches that only scan the current tmux window, this plugin uses **process tree detection**:

1. Runs `ps` to find all processes matching `copilot` (excluding `language-server`)
2. Builds a process tree from all running processes
3. Lists all tmux panes and their root PIDs
4. Maps each copilot process to its containing tmux pane via tree traversal
5. Caches the result until the target process exits

This means the Copilot CLI can be running in **any tmux session or window** — it doesn't need to be in the same window as Neovim.

### Sending Strategy

Uses `tmux load-buffer` + `tmux paste-buffer` instead of `tmux send-keys`. This is more reliable for:
- Long prompts with multiple lines
- Special characters and escape sequences
- Unicode content

## Troubleshooting

### "No Copilot CLI instance found"

- Make sure `copilot` is running in a tmux pane
- Check that the process is visible: `ps aux | grep copilot`
- Try manual target: set `tmux_target = "%42"` (find pane id with `tmux list-panes -a -F "#{pane_id} #{pane_current_command}"`)

### "Failed to send to Copilot CLI pane"

- Verify the tmux pane still exists
- Check tmux buffer permissions

### Debug Tips

```bash
# List all tmux panes with their commands
tmux list-panes -a -F '#{pane_id} #{pane_pid} #{pane_current_command}'

# Find copilot processes
ps -u $USER -ww -o pid,ppid,args | grep copilot

# Test manual send
tmux load-buffer -b test - <<< "hello"
tmux paste-buffer -b test -d -r -t %42
```

## License

MIT License
