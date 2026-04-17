local M = {}

-- Cache for detected target
M._target = nil -- { pid = number, pane_id = string, tool = string }

--- Supported CLI tools and their detection rules.
---@type { name: string, re: vim.regex, basename: string, excludes: string[] }[]
local cli_tools = {
  {
    name = "copilot",
    re = vim.regex("\\<copilot\\>"),
    basename = "copilot",
    excludes = { "language%-server" },
  },
  {
    name = "qodercli",
    re = vim.regex("\\<qodercli\\>"),
    basename = "qodercli",
    excludes = {},
  },
}

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

--- Check if a process command matches any supported CLI tool.
--- Returns the tool name on match, or nil.
---@param cmd_str string
---@return string?
local function match_cli_proc(cmd_str)
  -- Common exclusions for all tools
  if cmd_str:find("^nvim") or cmd_str:find("^%-?vim") then return nil end
  if cmd_str:find("^node") then return nil end

  local basename = cmd_str:match("^(%S+)")
  if not basename then return nil end
  basename = basename:match("([^/]+)$") or basename

  for _, tool in ipairs(cli_tools) do
    if tool.re:match_str(cmd_str) then
      local excluded = false
      for _, pattern in ipairs(tool.excludes) do
        if cmd_str:find(pattern) then
          excluded = true
          break
        end
      end
      if not excluded and basename == tool.basename then
        return tool.name
      end
    end
  end

  return nil
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

--- Find all running CLI tool processes (copilot and qodercli) via ps
---@return { pid: number, ppid: number, cmd: string, tool: string }[]
function M.find_cli_processes()
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
    if pid and ppid and args then
      local tool = match_cli_proc(args)
      if tool then
        table.insert(procs, {
          pid = tonumber(pid),
          ppid = tonumber(ppid),
          cmd = args,
          tool = tool,
        })
      end
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

---@param panes { pane_id: string, pid: number, cwd: string, session: string, window_index: string }[]
---@param cli_procs { pid: number, ppid: number, cmd: string, tool: string }[]
---@param children table<number, number[]>
---@param wanted_pane_id string?
---@return { pid: number, pane_id: string, cwd: string, session: string, window_index: string, tool: string }[]
local function build_targets(panes, cli_procs, children, wanted_pane_id)
  local targets = {}

  for _, pane in ipairs(panes) do
    if not wanted_pane_id or pane.pane_id == wanted_pane_id then
      for _, proc in ipairs(cli_procs) do
        if is_descendant(children, pane.pid, proc.pid) then
          table.insert(targets, {
            pid = proc.pid,
            pane_id = pane.pane_id,
            cwd = pane.cwd,
            session = pane.session,
            window_index = pane.window_index,
            tool = proc.tool,
          })
          break
        end
      end
    end
  end

  return targets
end

--- Find CLI tool instances and map them to tmux panes
---@return { pid: number, pane_id: string, cwd: string, session: string, window_index: string, tool: string }[]
function M.find_targets()
  local cli_procs = M.find_cli_processes()
  if #cli_procs == 0 then
    return {}
  end

  local panes = get_tmux_panes()
  if #panes == 0 then
    return {}
  end

  local children = build_process_tree()
  return build_targets(panes, cli_procs, children)
end

--- Check if the cached target is still alive
---@return boolean
function M.is_target_alive()
  if not M._target then
    return false
  end

  local cli_procs = M.find_cli_processes()
  if #cli_procs == 0 then
    return false
  end

  local panes = get_tmux_panes()
  if #panes == 0 then
    return false
  end

  local children = build_process_tree()
  local targets = build_targets(panes, cli_procs, children, M._target.pane_id)
  if #targets == 0 then
    return false
  end

  M._target = targets[1]
  return true
end

--- Get the current target pane_id, detecting if needed.
--- Returns pane_id or nil. If multiple targets found, prompts user to select.
---@param cb fun(pane_id: string?)
function M.get_target(cb)
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
      prompt = "Select CLI target:",
      format_item = function(item)
        local dir = vim.fn.fnamemodify(item.cwd, ":~")
        return string.format("[%s] %s (session: %s, window: %s)", item.tool, dir, item.session, item.window_index)
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
