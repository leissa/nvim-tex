--- okular viewer backend.
---
--- Inverse search cannot be configured from the command line; set
--- Settings -> Configure Okular -> Editor to "Custom Text Editor" with
---   nvim --server <servername> --remote-expr "v:lua.NvimTexInverseSearch(%l, '%f')"
--- See `:help nvim-tex-viewer-okular`.
local config = require('nvim-tex.config')
local util = require('nvim-tex.util')

local M = { name = 'okular' }

function M.available()
  return util.executable(config.get('view', 'okular', 'executable'))
end

---@param project table
---@param ctx table
---@return string[]
function M.spawn_cmd(_, ctx)
  local opts = config.get('view', 'okular')
  local cmd = util.as_cmd(opts.executable)
  vim.list_extend(cmd, opts.args or {})
  if ctx.line then
    cmd[#cmd + 1] = ('%s#src:%d %s'):format(ctx.pdf, ctx.line, ctx.tex)
  else
    cmd[#cmd + 1] = ctx.pdf
  end
  return cmd
end

--- `--unique` makes okular reuse the existing window.
function M.forward_cmd(project, ctx)
  return M.spawn_cmd(project, ctx)
end

return M
