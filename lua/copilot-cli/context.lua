local M = {}

local function get_current_file_path()
  local bufnr = vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(bufnr)
  return "@" .. vim.fn.fnamemodify(filename, ":~:.")
end

local function get_buffers_paths()
  local buffers = vim.api.nvim_list_bufs()
  local file_paths = {}

  for _, bufnr in ipairs(buffers) do
    if vim.bo[bufnr].buflisted then
      local filename = vim.api.nvim_buf_get_name(bufnr)
      if filename and filename ~= "" then
        local relative_path = vim.fn.fnamemodify(filename, ":~:.")
        if relative_path and relative_path ~= "" then
          table.insert(file_paths, "@" .. relative_path)
        end
      end
    end
  end

  if #file_paths == 0 then
    return "No buffers"
  end

  return table.concat(file_paths, " ")
end

-- Returns bufnr, relative file path, and cursor position,
-- resolving through floating windows to the underlying buffer.
local function get_cursor()
  local current_win = vim.api.nvim_get_current_win()
  local target_win = current_win

  local config = vim.api.nvim_win_get_config(current_win)
  if config.relative ~= "" then
    local prev_winnr = vim.fn.winnr("#")
    local prev_winid = vim.fn.win_getid(prev_winnr)
    if prev_winid ~= 0 and vim.api.nvim_win_is_valid(prev_winid) then
      target_win = prev_winid
    end
  end

  local bufnr = vim.api.nvim_win_get_buf(target_win)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local relative_path = vim.fn.fnamemodify(filename, ":~:.")
  local cursor = vim.api.nvim_win_get_cursor(target_win)
  return bufnr, relative_path, cursor
end

local function get_cursor_info()
  local _, relative_path, cursor = get_cursor()
  return string.format("@%s, Line: %d", relative_path, cursor[1])
end

local function get_visual_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local relative_path = vim.fn.fnamemodify(filename, ":~:.")

  local start_pos, end_pos
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    start_pos = vim.fn.getpos("v")
    end_pos = vim.fn.getpos(".")
    if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
      start_pos, end_pos = end_pos, start_pos
    end
  else
    start_pos = vim.fn.getpos("'<")
    end_pos = vim.fn.getpos("'>")
  end

  local start_line = start_pos[2]
  local end_line = end_pos[2]
  return relative_path, start_line, end_line
end

local function get_selection()
  local relative_path, start_line, end_line = get_visual_selection()
  return string.format("@%s:%d-%d", relative_path, start_line, end_line)
end

local function get_diagnostics()
  local bufnr, relative_path, cursor = get_cursor()
  local current_line = cursor[1] - 1

  local diagnostics = vim.diagnostic.get(bufnr, { lnum = current_line })
  if #diagnostics == 0 then
    return ""
  end

  local parts = { string.format("@%s", relative_path) }

  for _, diagnostic in ipairs(diagnostics) do
    local severity = vim.diagnostic.severity[diagnostic.severity]
    local line = diagnostic.lnum + 1
    local col = diagnostic.col + 1
    local message = string.format("[%s] Line %d, Col %d: %s", severity, line, col, diagnostic.message)
    if diagnostic.source then
      message = message .. string.format(" (%s)", diagnostic.source)
    end
    table.insert(parts, message)
  end

  return table.concat(parts, "\n")
end

function M.replace_placeholders(prompt)
  local replacements = {
    ["@buffers"] = get_buffers_paths,
    ["@file"] = get_current_file_path,
    ["@selection"] = get_selection,
    ["@diagnostics"] = get_diagnostics,
    ["@here"] = get_cursor_info,
  }

  for placeholder, func in pairs(replacements) do
    if prompt:find(placeholder, 1, true) then
      local replacement = func():gsub("%%", "%%%%")
      prompt = prompt:gsub(placeholder:gsub("[@]", "%%@"), replacement)
    end
  end

  return prompt
end

return M
