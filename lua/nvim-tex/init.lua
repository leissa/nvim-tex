--- nvim-tex: a Neovim-only LaTeX plugin built on LSP and tree-sitter.
---
--- Usage:
---   require('nvim-tex').setup({ ... })
--- Calling `setup` is optional; the defaults apply as soon as the plugin is
--- loaded. See `:help nvim-tex`.
local config = require('nvim-tex.config')

local M = {}

local augroup = vim.api.nvim_create_augroup('nvim-tex', { clear = true })
local initialised = false
local attached = {}

--- Buffer-local options that make Neovim behave sensibly in LaTeX files.
---@param bufnr integer
local function buffer_options(bufnr)
  vim.bo[bufnr].commentstring = '% %s'
  vim.bo[bufnr].comments = 's1:%%,mb:%%,el:%%,:%%'

  vim.api.nvim_buf_call(bufnr, function()
    -- `gf` and `:find` should understand `\input{foo}`.
    vim.opt_local.suffixesadd:prepend('.tex')
    vim.opt_local.include = [[\\\v(input|include|subfile)\{]]
    -- `<` and `>` are ordinary characters in LaTeX, not a pair.
    vim.opt_local.matchpairs:remove('<:>')
  end)
end

---@param bufnr integer
local function treesitter_setup(bufnr)
  local opts = config.get('treesitter')
  if not opts.enabled then
    return
  end

  local ts = require('nvim-tex.ts')
  if not ts.parser(bufnr) then
    return
  end

  if opts.highlight then
    pcall(vim.treesitter.start, bufnr, 'latex')
  end
  if opts.fold then
    vim.api.nvim_buf_call(bufnr, function()
      vim.opt_local.foldmethod = 'expr'
      vim.opt_local.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    end)
  end
end

--- Attach the plugin to `bufnr`.
---@param bufnr integer|nil
function M.attach(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if not config.get('enabled') or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- `nvim-tex.viewer` installs the global that viewers call back into, so it
  -- has to be loaded before any forward search can happen.
  require('nvim-tex.viewer')

  buffer_options(bufnr)
  treesitter_setup(bufnr)
  require('nvim-tex.lsp').attach(bufnr)
  require('nvim-tex.keymaps').attach(bufnr)

  if attached[bufnr] then
    return
  end
  attached[bufnr] = true

  if config.get('compiler', 'build_on_save') then
    vim.api.nvim_create_autocmd('BufWritePost', {
      group = augroup,
      buffer = bufnr,
      desc = 'nvim-tex: compile on save',
      callback = function()
        local compiler = require('nvim-tex.compiler')
        local project = require('nvim-tex.project').get(bufnr)
        if not compiler.is_running(project) then
          compiler.compile_single_shot(project)
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd('BufDelete', {
    group = augroup,
    buffer = bufnr,
    callback = function()
      attached[bufnr] = nil
      require('nvim-tex.project').invalidate(bufnr)
    end,
  })

  vim.api.nvim_exec_autocmds('User', { pattern = 'NvimTexAttach', data = { bufnr = bufnr } })
end

--- Register commands and the FileType hook. Safe to call repeatedly.
function M.init()
  if initialised then
    return
  end
  initialised = true

  require('nvim-tex.commands').setup()

  vim.api.nvim_create_autocmd('FileType', {
    group = augroup,
    pattern = config.get('filetypes'),
    desc = 'nvim-tex: attach to LaTeX buffers',
    callback = function(args)
      M.attach(args.buf)
    end,
  })

  -- Stop every compilation when Neovim exits, so no `latexmk -pvc` is left
  -- running in the background.
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = augroup,
    desc = 'nvim-tex: stop compilations on exit',
    callback = function()
      local project_mod = require('nvim-tex.project')
      local compiler = require('nvim-tex.compiler')
      for _, project in pairs(project_mod.projects) do
        if compiler.is_running(project) then
          project.compiler.stopping = true
          project.compiler.handle:kill('sigterm')
        end
      end
    end,
  })
end

---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  M.init()

  -- Re-attach buffers that were already open when `setup` ran.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.tbl_contains(config.get('filetypes'), vim.bo[bufnr].filetype) then
      M.attach(bufnr)
    end
  end
end

return M
