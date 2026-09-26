--- PDF viewer control: launching, forward search and inverse search.
local config = require('nvim-tex.config')
local project_mod = require('nvim-tex.project')
local util = require('nvim-tex.util')

local M = {}

M.backends = {
  zathura = require('nvim-tex.viewer.zathura'),
  sioyek = require('nvim-tex.viewer.sioyek'),
  okular = require('nvim-tex.viewer.okular'),
  skim = require('nvim-tex.viewer.skim'),
  general = require('nvim-tex.viewer.general'),
}

--- Order used by `view.method = 'auto'`.
local AUTO_ORDER = { 'zathura', 'sioyek', 'skim', 'okular', 'general' }

---@return table|nil
function M.backend()
  local method = config.get('view', 'method')
  if method == 'auto' then
    for _, name in ipairs(AUTO_ORDER) do
      local backend = M.backends[name]
      if backend and backend.available() then
        return backend
      end
    end
    util.error('no PDF viewer found; set view.method explicitly')
    return nil
  end

  local backend = M.backends[method]
  if not backend then
    util.error(("unknown view method '%s'"):format(tostring(method)))
    return nil
  end
  if not backend.available() then
    util.error(("viewer '%s' is not executable"):format(backend.name))
    return nil
  end
  return backend
end

--- Make sure this Neovim instance is reachable so the viewer can call back.
---@return string
local function ensure_server()
  if vim.v.servername ~= nil and vim.v.servername ~= '' then
    return vim.v.servername
  end
  local ok, address = pcall(vim.fn.serverstart)
  return ok and address or ''
end

---@param project table
---@return boolean
function M.is_running(project)
  local viewer = project.viewer
  if not viewer or not viewer.handle then
    return false
  end
  return viewer.handle:is_closing() ~= true
end

---@param project table
---@param opts table|nil `{ line = integer, col = integer, tex = string }`
---@return table
local function make_ctx(project, opts)
  opts = opts or {}
  return {
    pdf = project_mod.output_file(project, 'pdf'),
    tex = opts.tex or util.normalize(vim.api.nvim_buf_get_name(0)),
    line = opts.line,
    col = opts.col,
    server = ensure_server(),
  }
end

---@param cmd string[]
local function spawn(cmd, cwd)
  return vim.system(cmd, { cwd = cwd, detach = true, text = true }, function(result)
    if result.code ~= 0 and result.stderr and result.stderr ~= '' then
      local message = vim.trim(result.stderr)
      vim.schedule(function()
        util.warn('viewer: ' .. message)
      end)
    end
  end)
end

--- Open the PDF, doing a forward search to the cursor position.
---@param project table
---@param opts table|nil
function M.view(project, opts)
  if not config.get('view', 'enabled') then
    util.warn('viewer is disabled')
    return
  end

  local backend = M.backend()
  if not backend then
    return
  end

  opts = opts or {}
  local pdf = project_mod.output_file(project, 'pdf')
  if not util.is_file(pdf) then
    util.warn('no PDF yet: ' .. vim.fn.fnamemodify(pdf, ':~:.'))
    return
  end

  local want_search = opts.forward_search
  if want_search == nil then
    want_search = config.get('view', 'forward_search_on_start')
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local ctx = make_ctx(project, {
    line = want_search and cursor[1] or nil,
    col = want_search and (cursor[2] + 1) or nil,
    tex = opts.tex,
  })

  if M.is_running(project) then
    local cmd = backend.forward_cmd(project, ctx)
    if cmd then
      spawn(cmd, project.root)
      return
    end
    -- The backend cannot reach its running instance; fall through and spawn.
  end

  local handle = spawn(backend.spawn_cmd(project, ctx), project.root)
  project.viewer = { handle = handle, pid = handle.pid, backend = backend.name }
end

--- Forward search only: never launches a viewer that is not already running.
---@param project table
function M.forward_search(project)
  local backend = M.backend()
  if not backend then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local ctx = make_ctx(project, { line = cursor[1], col = cursor[2] + 1 })

  if M.is_running(project) then
    local cmd = backend.forward_cmd(project, ctx)
    if cmd then
      spawn(cmd, project.root)
      return
    end
  end
  M.view(project, { forward_search = true })
end

--- Ask the viewer to jump back to the editor.
---
--- Most viewers push this direction themselves (ctrl-click in zathura,
--- shift-click in okular), which the launch command already wires up. Only a
--- few expose a pull API.
---@param project table
function M.reverse_search(project)
  if not M.is_running(project) then
    util.warn('no viewer running')
    return
  end
  local backend = M.backends[project.viewer.backend]
  if backend and backend.reverse_cmd then
    spawn(backend.reverse_cmd(project, make_ctx(project)), project.root)
    return
  end
  util.info(
    ("%s performs inverse search itself -- use its own binding (ctrl-click in zathura, shift-click in okular)"):format(
      project.viewer.backend
    )
  )
end

--- Entry point for viewers doing inverse search.
---
--- Exposed as a global so viewers can call it over `--remote-expr` with
--- `v:lua.NvimTexInverseSearch(<line>, '<file>')`.
---@param line integer
---@param file string
---@return integer
function _G.NvimTexInverseSearch(line, file)
  vim.schedule(function()
    local path = util.normalize(file)
    if not util.is_file(path) then
      util.warn('inverse search: no such file ' .. file)
      return
    end

    -- Prefer a window that already shows the file.
    local bufnr = vim.fn.bufnr(path)
    local winid = bufnr >= 0 and vim.fn.bufwinid(bufnr) or -1
    if winid ~= -1 then
      vim.api.nvim_set_current_win(winid)
    else
      vim.cmd('edit ' .. vim.fn.fnameescape(path))
    end

    local target = math.max(1, math.min(tonumber(line) or 1, vim.api.nvim_buf_line_count(0)))
    vim.api.nvim_win_set_cursor(0, { target, 0 })
    vim.cmd('normal! zz')
    vim.api.nvim_exec_autocmds('User', { pattern = 'NvimTexInverseSearch', data = { file = path, line = target } })
  end)
  return 0
end

--- Close the viewer belonging to `project`.
---@param project table
function M.close(project)
  if M.is_running(project) then
    project.viewer.handle:kill('sigterm')
    project.viewer = nil
  end
end

return M
