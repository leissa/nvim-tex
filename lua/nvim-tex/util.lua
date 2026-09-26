--- Small helpers shared across the plugin.
local M = {}

local PREFIX = '[nvim-tex] '

---@param msg string
---@param level integer|nil
function M.notify(msg, level)
  vim.notify(PREFIX .. msg, level or vim.log.levels.INFO)
end

function M.info(msg)
  M.notify(msg, vim.log.levels.INFO)
end

function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

function M.error(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

--- Notify unless the caller asked for silence.
function M.info_unless(silent, msg)
  if not silent then
    M.info(msg)
  end
end

---@param name string
---@return boolean
function M.executable(name)
  return vim.fn.executable(name) == 1
end

--- Normalise a path: expand `~`, resolve `.`/`..`, drop trailing slashes.
---@param path string
---@return string
function M.normalize(path)
  return (vim.fs.normalize(vim.fn.fnamemodify(path, ':p')):gsub('/+$', ''))
end

---@param ... string
---@return string
function M.join(...)
  return (table.concat({ ... }, '/'):gsub('//+', '/'))
end

---@param path string
---@return boolean
function M.is_file(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == 'file'
end

---@param path string
---@return boolean
function M.is_dir(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == 'directory'
end

function M.mkdir(path)
  vim.fn.mkdir(path, 'p')
end

--- Read a file as a list of lines. Returns an empty list when unreadable.
---@param path string
---@param max integer|nil stop after this many lines
---@return string[]
function M.readlines(path, max)
  local fd = vim.uv.fs_open(path, 'r', 438)
  if not fd then
    return {}
  end
  local stat = vim.uv.fs_fstat(fd)
  local data = stat and vim.uv.fs_read(fd, stat.size, 0) or ''
  vim.uv.fs_close(fd)

  local lines = vim.split(data or '', '\n', { plain = true })
  if lines[#lines] == '' then
    table.remove(lines)
  end
  if max and #lines > max then
    lines = vim.list_slice(lines, 1, max)
  end
  return lines
end

---@param path string
---@param lines string[]
function M.writelines(path, lines)
  M.mkdir(vim.fs.dirname(path))
  local fd = vim.uv.fs_open(path, 'w', 420)
  if not fd then
    return
  end
  vim.uv.fs_write(fd, table.concat(lines, '\n') .. '\n', 0)
  vim.uv.fs_close(fd)
end

--- Resolve a config value that may be a string or a function of `file_info`.
---@param value any
---@param file_info table
---@return any
function M.resolve(value, file_info)
  if type(value) == 'function' then
    return value(file_info)
  end
  return value
end

--- Coerce a string-or-list executable spec into a command list.
---@param exe string|string[]
---@return string[]
function M.as_cmd(exe)
  if type(exe) == 'table' then
    return vim.deepcopy(exe)
  end
  return { exe }
end

--- Escape a replacement string for use in `string.gsub`.
---@param s string
function M.escape_replacement(s)
  return (s:gsub('%%', '%%%%'))
end

--- Substitute `@pdf`, `@line`, `@col`, `@tex`, `@server` placeholders.
---@param args string[]
---@param subs table<string, string>
---@return string[]
function M.expand_args(args, subs)
  local out = {}
  for _, arg in ipairs(args) do
    local value = arg
    for key, replacement in pairs(subs) do
      value = value:gsub('@' .. key, M.escape_replacement(tostring(replacement)))
    end
    out[#out + 1] = value
  end
  return out
end

--- Open a scratch buffer in a split and fill it with `lines`.
---@param name string
---@param lines string[]
---@param opts table|nil
---@return integer bufnr
function M.scratch(name, lines, opts)
  opts = opts or {}
  local bufnr = vim.fn.bufnr(name)
  if bufnr < 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, name)
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].bufhidden = 'hide'
  vim.bo[bufnr].swapfile = false
  if opts.filetype then
    vim.bo[bufnr].filetype = opts.filetype
  end

  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    vim.cmd(opts.split or 'botright split')
    winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    if opts.height then
      vim.api.nvim_win_set_height(winid, opts.height)
    end
  else
    vim.api.nvim_set_current_win(winid)
  end

  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.keymap.set('n', 'q', '<Cmd>close<CR>', { buffer = bufnr, nowait = true })

  return bufnr
end

return M
