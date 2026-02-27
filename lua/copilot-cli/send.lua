local M = {}

--- Send text to a tmux pane via bracketed paste.
--- TUI apps (like copilot CLI) require bracketed paste escape sequences to
--- accept pasted text into their input fields. Plain send-keys is silently ignored.
--- Uses tmux load-buffer (with stdin) + paste-buffer to deliver the text.
---@param pane_id string tmux pane identifier (e.g., "%36")
---@param text string text to send
---@return boolean success
function M.send(pane_id, text)
  local paste_data = string.format("\027[200~%s\027[201~", text)
  local r1 = vim.system({ "tmux", "load-buffer", "-" }, { stdin = paste_data }):wait()
  if r1.code ~= 0 then
    return false
  end
  local r2 = vim.system({ "tmux", "paste-buffer", "-t", pane_id }):wait()
  return r2.code == 0
end

--- Submit the input in the target pane
---@param pane_id string
---@param submit_key string tmux key name (e.g., "Enter", "C-q")
---@return boolean
function M.submit(pane_id, submit_key)
  local r = vim.system({ "tmux", "send-keys", "-t", pane_id, submit_key }):wait()
  return r.code == 0
end

return M
