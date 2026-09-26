--- zathura viewer backend.
---
--- Forward search on an already running instance goes through zathura's D-Bus
--- interface, which is the only way to reach a specific instance. Without
--- `dbus-send` we fall back to re-launching, which opens a second window.
local config = require('nvim-tex.config')
local util = require('nvim-tex.util')

local M = { name = 'zathura' }

function M.available()
  return util.executable(config.get('view', 'zathura', 'executable'))
end

---@param ctx table
---@return string
local function editor_command(ctx)
  return ('%s --server %s --remote-expr "v:lua.NvimTexInverseSearch(%%{line}, \'%%{input}\')"'):format(
    vim.v.progpath,
    ctx.server
  )
end

---@param project table
---@param ctx table
---@return string[]
function M.spawn_cmd(project, ctx)
  local opts = config.get('view', 'zathura')
  local cmd = util.as_cmd(opts.executable)
  vim.list_extend(cmd, opts.args or {})
  if ctx.server ~= '' then
    cmd[#cmd + 1] = '-x'
    cmd[#cmd + 1] = editor_command(ctx)
  end
  if ctx.line then
    cmd[#cmd + 1] = '--synctex-forward'
    cmd[#cmd + 1] = ('%d:%d:%s'):format(ctx.line, ctx.col, ctx.tex)
  end
  cmd[#cmd + 1] = ctx.pdf
  return cmd
end

---@param project table
---@param ctx table
---@return string[]|nil nil means "no way to reach the running instance"
function M.forward_cmd(project, ctx)
  local opts = config.get('view', 'zathura')
  local pid = project.viewer and project.viewer.pid
  if not (opts.use_dbus and pid and util.executable('dbus-send')) then
    return nil
  end
  return {
    'dbus-send',
    '--session',
    '--type=method_call',
    '--dest=org.pwmt.zathura.PID-' .. pid,
    '/org/pwmt/zathura',
    'org.pwmt.zathura.SynctexView',
    'int32:' .. ctx.line,
    'int32:' .. ctx.col,
    'string:' .. ctx.tex,
  }
end

return M
