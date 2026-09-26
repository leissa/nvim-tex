--- sioyek viewer backend.
local config = require('nvim-tex.config')
local util = require('nvim-tex.util')

local M = { name = 'sioyek' }

function M.available()
  return util.executable(config.get('view', 'sioyek', 'executable'))
end

---@param ctx table
---@return string
local function inverse_search(ctx)
  return ('%s --server %s --remote-expr "v:lua.NvimTexInverseSearch(%%2, \'%%1\')"'):format(
    vim.v.progpath,
    ctx.server
  )
end

---@param project table
---@param ctx table
---@return string[]
function M.spawn_cmd(_, ctx)
  local opts = config.get('view', 'sioyek')
  local cmd = util.as_cmd(opts.executable)
  vim.list_extend(cmd, opts.args or {})
  cmd[#cmd + 1] = '--reuse-window'
  if ctx.server ~= '' then
    cmd[#cmd + 1] = '--inverse-search'
    cmd[#cmd + 1] = inverse_search(ctx)
  end
  if ctx.line then
    vim.list_extend(cmd, {
      '--forward-search-file',
      ctx.tex,
      '--forward-search-line',
      tostring(ctx.line),
    })
  end
  cmd[#cmd + 1] = ctx.pdf
  return cmd
end

--- sioyek reuses its window when `--reuse-window` is given, so forward search
--- is just another invocation.
function M.forward_cmd(project, ctx)
  return M.spawn_cmd(project, ctx)
end

return M
