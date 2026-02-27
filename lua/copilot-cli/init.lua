local M = {}
local context = require("copilot-cli.context")
local detect = require("copilot-cli.detect")
local send = require("copilot-cli.send")

M.config = {
  auto_detect = true,
  tmux_target = nil, -- Manual override: tmux pane id (e.g., "%42")
  auto_submit = true, -- Automatically submit after sending
  submit_key = "C-q", -- Key to submit prompt (C-q for autopilot mode, Enter for interactive)
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

    if M.config.auto_submit then
      send.submit(pane_id, M.config.submit_key)
    end

    vim.notify(string.format("Sent prompt to Copilot CLI (%s)", pane_id), vim.log.levels.INFO)
    sent = true
  end)

  return sent
end

--- Open vim.ui.input prompt, process placeholders, and send
function M.send_prompt()
  local mode = vim.fn.mode()
  local default_text = ""
  if mode == "v" or mode == "V" or mode == "\22" then
    default_text = "@selection "
  end

  vim.ui.input({
    prompt = "Copilot CLI (@file, @buffers, @here, @selection, @diagnostics): ",
    default = default_text,
  }, function(input)
    if not input or input == "" then
      return
    end

    local processed = context.replace_placeholders(input)
    send_to_copilot(processed)
  end)
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
