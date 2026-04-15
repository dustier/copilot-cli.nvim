local M = {}
local context = require("copilot-cli.context")
local detect = require("copilot-cli.detect")
local send = require("copilot-cli.send")

--- Send processed prompt to the detected CLI target
---@param message string raw prompt text (placeholders already replaced)
---@return boolean
local function send_to_target(message)
  local sent = false

  detect.get_target(function(pane_id)
    if not pane_id then
      vim.notify(
        "No CLI target found. Make sure `copilot` or `qodercli` is running in a tmux pane.",
        vim.log.levels.ERROR
      )
      return
    end

    local ok = send.send(pane_id, message)
    if not ok then
      vim.notify("Failed to send to CLI pane", vim.log.levels.ERROR)
      return
    end

    local tool = detect._target and detect._target.tool or "CLI"
    vim.notify(string.format("Sent prompt to %s (%s)", tool, pane_id), vim.log.levels.INFO)
    sent = true
  end)

  return sent
end

---@return { width: integer, height: integer, row: integer, col: integer, anchor_bottom: integer, max_height: integer }
local function get_prompt_layout()
  local cursor_screenpos = vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col("."))
  local anchor_bottom = math.max(1, cursor_screenpos.row - 1)
  local col = math.max(0, cursor_screenpos.col - 1)
  local max_width = math.max(1, math.min(80, vim.o.columns - 2))
  local width = math.max(1, math.min(max_width, vim.o.columns - col - 2))

  if width < math.min(30, max_width) then
    width = max_width
    col = math.max(0, vim.o.columns - width - 2)
  end

  local max_height = math.max(1, math.min(10, vim.o.lines - 4))
  local height = 1
  local row = math.max(0, anchor_bottom - height - 2)

  return {
    width = width,
    height = height,
    row = row,
    col = col,
    anchor_bottom = anchor_bottom,
    max_height = max_height,
  }
end

---@param buf integer
---@param width integer
---@return integer
local function get_prompt_height(buf, width)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local total = 0

  for _, line in ipairs(lines) do
    local display_width = vim.fn.strdisplaywidth(line)
    total = total + math.max(1, math.ceil(math.max(1, display_width) / math.max(1, width)))
  end

  return math.max(1, total)
end

---@param buf integer
---@param win integer
local function configure_prompt_window(buf, win)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].showbreak = ""
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].spell = false

  if vim.fn.exists("+statuscolumn") == 1 then
    vim.wo[win].statuscolumn = ""
  end
  if vim.fn.exists("+winfixbuf") == 1 then
    vim.wo[win].winfixbuf = true
  end
end

---@param default_text string
local function open_prompt_editor(default_text)
  local layout = get_prompt_layout()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default_text })

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = layout.row,
    col = layout.col,
    width = layout.width,
    height = layout.height,
    style = "minimal",
    border = "rounded",
    title = " AI CLI Prompt ",
    title_pos = "center",
  })

  configure_prompt_window(buf, win)

  local function resize()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end

    local height = math.min(layout.max_height, get_prompt_height(buf, layout.width))
    local row = math.max(0, layout.anchor_bottom - height - 2)
    vim.api.nvim_win_set_config(win, {
      relative = "editor",
      row = row,
      col = layout.col,
      width = layout.width,
      height = height,
    })
  end

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      resize()
    end,
  })

  local closed = false
  local function close()
    if closed then
      return
    end
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

    if not input:match("%S") then
      return
    end

    local processed = context.replace_placeholders(input)
    send_to_target(processed)
  end

  local opts = { buffer = buf, silent = true }
  vim.keymap.set({ "i", "n" }, "<C-s>", submit, opts)
  vim.keymap.set({ "i", "n" }, "<C-c>", close, opts)
  vim.keymap.set("n", "<CR>", submit, opts)
  vim.keymap.set("n", "q", close, opts)

  resize()
  vim.api.nvim_win_set_cursor(win, { 1, #default_text })
  vim.cmd("startinsert!")
end

--- Open a floating prompt editor, process placeholders, and send
function M.send_prompt()
  local mode = vim.fn.mode()
  local default_text = ""
  if mode == "v" or mode == "V" or mode == "\22" then
    default_text = "@selection "
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  end

  open_prompt_editor(default_text)
end

--- Re-detect / select target CLI instance
function M.select_target()
  detect.clear_target()
  detect.get_target(function(pane_id)
    if pane_id then
      local tool = detect._target and detect._target.tool or "CLI"
      vim.notify(string.format("Selected %s target: %s", tool, pane_id), vim.log.levels.INFO)
    else
      vim.notify("No CLI target found.", vim.log.levels.WARN)
    end
  end)
end

function M.setup(opts)
end

return M
