local M = {}

-- Cache for detected target
M._target = nil -- { pid = number, pane_id = string }

local copilot_re = vim.regex("\\<copilot\\>")

--- Execute a command and return stdout lines
---@param cmd string[]
---@return string[]?
local function exec(cmd)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 or not result.stdout or result.stdout == "" then
    return nil
  end
  return vim.split(result.stdout, "\n", { plain = true, trimempty = true })
end

--- Check if a process command matches copilot CLI (not language-server, not nvim, not node)
---@param cmd_str string
---@return boolean
local function is_copilot_proc(cmd_str)
  if not copilot_re:match_str(cmd_str) then
    return false
  end
  -- Exclude processes that merely contain "copilot" in paths or arguments
  if cmd_str:find("language%-server") then return false end
  if cmd_str:find("^nvim") or cmd_str:find("^%-?vim") then return false end
  if cmd_str:find("^node") then return false end
  -- The command should start with "copilot" or have copilot as the main executable
  local basename = cmd_str:match("^(%S+)")
  if basename then
    basename = basename:match("([^/]+)$") or basename
    if basename == "copilot" then return true end
  end
  return false
end

--- Build ps command with user filter when available, falling back to -e
---@return string[]
local function ps_cmd()
  local cmd = { "ps" }
  local user = vim.env.USER
  if not user or user == "" then
    user = vim.fn.system("whoami"):gsub("%s+$", "")
  end
  if user ~= "" then
    vim.list_extend(cmd, { "-u", user })
  else
    table.insert(cmd, "-e")
  end
  return cmd
end

--- Find all running copilot processes via ps
---@return { pid: number, ppid: number, cmd: string }[]
function M.find_copilot_processes()
  local cmd = ps_cmd()
  vim.list_extend(cmd, { "-ww", "-o", "pid,ppid,args" })

  local lines = exec(cmd)
  if not lines then
    return {}
  end

  local procs = {}
  -- Skip header line
  for i = 2, #lines do
    local pid, ppid, args = lines[i]:match("^%s*(%d+)%s+(%d+)%s+(.*)$")
    if pid and ppid and args and is_copilot_proc(args) then
      table.insert(procs, {
        pid = tonumber(pid),
        ppid = tonumber(ppid),
        cmd = args,
      })
    end
  end

  return procs
end

--- Build a pid -> children mapping from ps output
---@return table<number, number[]>
local function build_process_tree()
  local cmd = ps_cmd()
  vim.list_extend(cmd, { "-ww", "-o", "pid,ppid" })

  local lines = exec(cmd)
  if not lines then
    return {}
  end

  local children = {}
  for i = 2, #lines do
    local pid, ppid = lines[i]:match("^%s*(%d+)%s+(%d+)")
    if pid and ppid then
      pid = tonumber(pid)
      ppid = tonumber(ppid)
      children[ppid] = children[ppid] or {}
      table.insert(children[ppid], pid)
    end
  end

  return children
end

--- Check if target_pid is a descendant of root_pid
---@param children table<number, number[]>
---@param root_pid number
---@param target_pid number
---@return boolean
local function is_descendant(children, root_pid, target_pid)
  local queue = { root_pid }
  while #queue > 0 do
    local current = table.remove(queue, 1)
    if current == target_pid then
      return true
    end
    for _, child in ipairs(children[current] or {}) do
      table.insert(queue, child)
    end
  end
  return false
end

--- Get all tmux panes with their PIDs
--- Get all tmux panes with their PIDs and metadata
---@return { pane_id: string, pid: number, cwd: string, session: string, window_index: string }[]
local function get_tmux_panes()
  local lines = exec({
    "tmux", "list-panes", "-a",
    "-F", "#{pane_id}\t#{pane_pid}\t#{pane_current_path}\t#{session_name}\t#{window_index}",
  })
  if not lines then
    return {}
  end

  local panes = {}
  for _, line in ipairs(lines) do
    local pane_id, pid, cwd, session, win_idx = line:match("^(%%%d+)\t(%d+)\t(.-)\t(.-)\t(.+)$")
    if pane_id and pid then
      table.insert(panes, {
        pane_id = pane_id,
        pid = tonumber(pid),
        cwd = cwd or "",
        session = session or "",
        window_index = win_idx or "",
      })
    end
  end

  return panes
end

--- Find copilot instances and map them to tmux panes
---@return { pid: number, pane_id: string, cwd: string, session: string, window_index: string }[]
function M.find_targets()
  local copilot_procs = M.find_copilot_processes()
  if #copilot_procs == 0 then
    return {}
  end

  local panes = get_tmux_panes()
  if #panes == 0 then
    return {}
  end

  local children = build_process_tree()
  local targets = {}

  for _, proc in ipairs(copilot_procs) do
    for _, pane in ipairs(panes) do
      if is_descendant(children, pane.pid, proc.pid) then
        table.insert(targets, {
          pid = proc.pid,
          pane_id = pane.pane_id,
          cwd = pane.cwd,
          session = pane.session,
          window_index = pane.window_index,
        })
        break
      end
    end
  end

  return targets
end

--- Check if the cached target is still alive and still a copilot process
---@return boolean
function M.is_target_alive()
  if not M._target then
    return false
  end
  local proc = vim.api.nvim_get_proc(M._target.pid)
  if not proc then
    return false
  end
  return proc.name == "copilot"
end

--- Get the current target pane_id, detecting if needed.
--- Returns pane_id or nil. If multiple targets found, prompts user to select.
---@param manual_target string? manual tmux pane override
---@param cb fun(pane_id: string?)
function M.get_target(manual_target, cb)
  if manual_target then
    cb(manual_target)
    return
  end

  if M.is_target_alive() then
    cb(M._target.pane_id)
    return
  end

  -- Need to detect
  M._target = nil
  local targets = M.find_targets()

  if #targets == 0 then
    cb(nil)
  elseif #targets == 1 then
    M._target = targets[1]
    cb(targets[1].pane_id)
  else
    -- Multiple targets, let user choose
    vim.ui.select(targets, {
      prompt = "Select Copilot CLI instance:",
      format_item = function(item)
        local dir = vim.fn.fnamemodify(item.cwd, ":~")
        return string.format("%s (session: %s, window: %s)", dir, item.session, item.window_index)
      end,
    }, function(choice)
      if choice then
        M._target = choice
        cb(choice.pane_id)
      else
        cb(nil)
      end
    end)
  end
end

--- Clear cached target (force re-detection)
function M.clear_target()
  M._target = nil
end

return M
