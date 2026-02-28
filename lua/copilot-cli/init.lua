local M = {}
local context = require("copilot-cli.context")
local detect = require("copilot-cli.detect")
local send = require("copilot-cli.send")

M.config = {
  auto_detect = true,
  tmux_target = nil, -- Manual override: tmux pane id (e.g., "%42")
}

--- Send processed prompt to the detected copilot CLI instance
---@param message string raw prompt text (placeholders already replaced)
---@return boolean
local function send_to_copilot(message)
  local sent = false

  detect.get_target(M.config.tmux_target, function(pane_id)
    if not pane_id then
      vim.notify(
        "No Copilot CLI instance found. Make sure `copilot` is running in a tmux pane.",
        vim.log.levels.ERROR
      )
      return
    end

    local ok = send.send(pane_id, message)
    if not ok then
      vim.notify("Failed to send to Copilot CLI pane", vim.log.levels.ERROR)
      return
    end

    vim.notify(string.format("Sent prompt to Copilot CLI (%s)", pane_id), vim.log.levels.INFO)
    sent = true
  end)

  return sent
end

--- Open a floating input near the cursor, process placeholders, and send
function M.send_prompt()
  local mode = vim.fn.mode()
  local default_text = ""
  if mode == "v" or mode == "V" or mode == "\22" then
    default_text = "@selection "
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  end

  -- Anchor position: above cursor
  local cursor_screenpos = vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col("."))
  local anchor_bottom = cursor_screenpos.row - 1
  local col = cursor_screenpos.col - 1
  local max_height = 10

  local width = math.min(80, vim.o.columns - col - 2)
  if width < 30 then
    col = math.max(0, vim.o.columns - 82)
    width = math.min(80, vim.o.columns - col - 2)
  end

  local initial_height = 1
  local row = math.max(0, anchor_bottom - initial_height - 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default_text })
  vim.bo[buf].buftype = "nofile"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = initial_height,
    style = "minimal",
    border = "rounded",
    title = " Copilot CLI (C-s to send) ",
    title_pos = "center",
  })

  vim.wo[win].wrap = true

  vim.cmd("startinsert!")

  -- Auto-resize window as content changes
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if not vim.api.nvim_win_is_valid(win) then
        return true
      end
      local line_count = vim.api.nvim_buf_line_count(buf)
      local new_height = math.max(1, math.min(line_count, max_height))
      local new_row = math.max(0, anchor_bottom - new_height - 2)
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        row = new_row,
        col = col,
        width = width,
        height = new_height,
      })
    end,
  })

  local closed = false
  local function close()
    if closed then return end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = table.concat(lines, "\n")
    close()
    if not input or not input:match("%S") then
      return
    end
    local processed = context.replace_placeholders(input)
    send_to_copilot(processed)
  end

  local opts = { buffer = buf, silent = true }
  vim.keymap.set("i", "<C-s>", submit, opts)
  vim.keymap.set("n", "<CR>", submit, opts)
  vim.keymap.set("i", "<Esc>", "<Esc>", opts)
  vim.keymap.set("n", "<Esc>", close, opts)
  vim.keymap.set("n", "q", close, opts)
end

--- Re-detect / select target copilot CLI instance
function M.select_target()
  detect.clear_target()
  detect.get_target(nil, function(pane_id)
    if pane_id then
      vim.notify(string.format("Selected Copilot CLI target: %s", pane_id), vim.log.levels.INFO)
    else
      vim.notify("No Copilot CLI instance found.", vim.log.levels.WARN)
    end
  end)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
