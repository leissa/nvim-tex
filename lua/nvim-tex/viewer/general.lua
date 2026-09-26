--- Generic viewer backend: runs a user supplied command.
---
--- The placeholders `@pdf`, `@tex`, `@line`, `@col` and `@server` are
--- substituted in `view.general.args`.
local config = require('nvim-tex.config')
local util = require('nvim-tex.util')

local M = { name = 'general' }

function M.available()
  return util.executable(config.get('view', 'general', 'executable'))
end

---@param project table
---@param ctx table
---@return string[]
function M.spawn_cmd(_, ctx)
  local opts = config.get('view', 'general')
  local cmd = util.as_cmd(opts.executable)
  vim.list_extend(
    cmd,
    util.expand_args(opts.args or { '@pdf' }, {
      pdf = ctx.pdf,
      tex = ctx.tex,
      line = ctx.line or 1,
      col = ctx.col or 1,
      server = ctx.server,
    })
  )
  return cmd
end

--- No way to know whether a generic viewer supports forward search.
function M.forward_cmd()
  return nil
end

return M
