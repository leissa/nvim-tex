--- `:checkhealth nvim-tex`
local config = require('nvim-tex.config')
local util = require('nvim-tex.util')

local M = {}

---@param name string
---@param advice string|nil
---@param required boolean
local function check_executable(name, advice, required)
  if util.executable(name) then
    vim.health.ok(("'%s' found (%s)"):format(name, vim.fn.exepath(name)))
  elseif required then
    vim.health.error(("'%s' not found"):format(name), advice and { advice } or nil)
  else
    vim.health.warn(("'%s' not found"):format(name), advice and { advice } or nil)
  end
end

function M.check()
  vim.health.start('nvim-tex')

  if vim.fn.has('nvim-0.10') == 1 then
    vim.health.ok('Neovim ' .. tostring(vim.version()))
  else
    vim.health.error('Neovim 0.10 or newer is required')
  end

  vim.health.start('nvim-tex: tree-sitter')
  local ok, parsers = pcall(vim.treesitter.language.add, 'latex')
  if ok and parsers ~= false then
    vim.health.ok("the 'latex' parser is installed")
  else
    vim.health.error("the 'latex' parser is missing", {
      'Install it with :TSInstall latex, or with your parser manager of choice.',
    })
  end

  vim.health.start('nvim-tex: LSP')
  if config.get('lsp', 'enabled') then
    check_executable(config.get('lsp', 'cmd')[1], 'Install texlab: https://github.com/latex-lsp/texlab', false)
  else
    vim.health.info('LSP integration is disabled (lsp.enabled = false)')
  end

  vim.health.start('nvim-tex: compiler')
  local latexmk = config.get('compiler', 'latexmk', 'executable')
  check_executable(type(latexmk) == 'table' and latexmk[1] or latexmk, 'latexmk ships with TeX Live and MiKTeX.', true)

  vim.health.start('nvim-tex: viewer')
  local method = config.get('view', 'method')
  local viewer = require('nvim-tex.viewer')
  if method == 'auto' then
    local backend = viewer.backend()
    if backend then
      vim.health.ok(('auto-detected viewer: %s'):format(backend.name))
    else
      vim.health.warn('no supported PDF viewer found', {
        'Install zathura, sioyek or okular, or set view.method = "general".',
      })
    end
  else
    local backend = viewer.backends[method]
    if backend and backend.available() then
      vim.health.ok(('viewer %s is available'):format(method))
    else
      vim.health.error(('viewer %s is not available'):format(method))
    end
  end
  check_executable('dbus-send', 'Needed for zathura forward search into a running instance.', false)

  vim.health.start('nvim-tex: optional tools')
  check_executable('texdoc', 'Needed for the K mapping (package documentation).', false)
  check_executable('latexindent', 'Used by texlab for formatting.', false)

  vim.health.start('nvim-tex: server')
  if vim.v.servername ~= nil and vim.v.servername ~= '' then
    vim.health.ok('server address: ' .. vim.v.servername)
  else
    vim.health.warn('no server address; it is started on demand for inverse search')
  end
end

return M
