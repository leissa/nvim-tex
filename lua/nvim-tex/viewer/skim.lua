--- Skim viewer backend (macOS).
local config = require('nvim-tex.config')
local util = require('nvim-tex.util')

local M = { name = 'skim' }

function M.available()
  return util.executable(config.get('view', 'skim', 'executable'))
end

---@param project table
---@param ctx table
---@return string[]
function M.spawn_cmd(_, ctx)
  local opts = config.get('view', 'skim')
  local cmd = util.as_cmd(opts.executable)
  vim.list_extend(cmd, opts.args or {})
  -- `-r` keeps the focus in the editor, `-g` opens in the background.
  vim.list_extend(cmd, { '-r', '-g', tostring(ctx.line or 1), ctx.pdf, ctx.tex })
  return cmd
end

function M.forward_cmd(project, ctx)
  return M.spawn_cmd(project, ctx)
end

return M
