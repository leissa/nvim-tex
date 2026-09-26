--- texlab integration.
---
--- The server is started per project root with `vim.lsp.start`, which reuses
--- an existing client when one already matches. If you configure texlab
--- yourself (nvim-lspconfig, `vim.lsp.enable`, ...), set `lsp.enabled = false`
--- or simply let the duplicate check below back off.
local config = require('nvim-tex.config')
local project_mod = require('nvim-tex.project')
local util = require('nvim-tex.util')

local M = {}

local warned = false

--- Is a client with this name already attached to `bufnr`?
---@param bufnr integer
---@param name string
---@return boolean
local function already_attached(bufnr, name)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == name then
      return true
    end
  end
  return false
end

--- Start (or reuse) texlab for `bufnr`.
---@param bufnr integer
---@return integer|nil client_id
function M.attach(bufnr)
  local opts = config.get('lsp')
  if not opts.enabled then
    return nil
  end
  if already_attached(bufnr, opts.name) then
    return nil
  end

  local cmd = opts.cmd
  if not util.executable(cmd[1]) then
    if not warned then
      warned = true
      util.warn(("'%s' not found; LSP features are unavailable"):format(cmd[1]))
    end
    return nil
  end

  local project = project_mod.get(bufnr)
  local client_config = vim.tbl_deep_extend('force', {
    name = opts.name,
    cmd = cmd,
    root_dir = project.root,
    settings = opts.settings,
    -- texlab reports progress for its own builds and for forward search;
    -- both are driven by nvim-tex here, so the noise is not useful.
    single_file_support = true,
  }, opts.config or {})

  local ok, client_id = pcall(vim.lsp.start, client_config, { bufnr = bufnr })
  if not ok then
    util.error('failed to start ' .. opts.name .. ': ' .. tostring(client_id))
    return nil
  end
  return client_id
end

--- The texlab client attached to `bufnr`, if any.
---@param bufnr integer|nil
---@return vim.lsp.Client|nil
function M.client(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == config.get('lsp', 'name') then
      return client
    end
  end
  return nil
end

--- Run a texlab workspace command (`texlab.cleanAuxiliary`, ...).
---@param command string
---@param arguments table|nil
function M.execute(command, arguments)
  local client = M.client()
  if not client then
    util.warn('no texlab client attached')
    return
  end
  client:exec_cmd({ title = command, command = command, arguments = arguments })
end

--- texlab's structural "change environment" command, used as a fallback when
--- the tree-sitter parser is unavailable.
---@param new_name string
function M.change_environment(new_name)
  local client = M.client()
  if not client then
    util.warn('no texlab client attached')
    return
  end
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.newName = new_name
  client:request('workspace/executeCommand', {
    command = 'texlab.changeEnvironment',
    arguments = { params },
  })
end

--- Ask texlab for the document symbols and return them flattened.
---@param bufnr integer|nil
---@param callback fun(symbols: table[])
function M.document_symbols(bufnr, callback)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local client = M.client(bufnr)
  if not client then
    callback({})
    return
  end
  client:request('textDocument/documentSymbol', {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
  }, function(err, result)
    callback((not err and result) or {})
  end, bufnr)
end

return M
