local H = require('tests.helpers')
local config = require('nvim-tex.config')
local nvim_tex = require('nvim-tex')

--- Every command `nvim-tex.commands` is meant to register.
local COMMANDS = {
  'TexClean',
  'TexCompile',
  'TexCompileOutput',
  'TexCompileSS',
  'TexCompileSelected',
  'TexContextMenu',
  'TexDocPackage',
  'TexEnvSurround',
  'TexErrors',
  'TexForwardSearch',
  'TexImaps',
  'TexInfo',
  'TexLog',
  'TexQfLevel',
  'TexReload',
  'TexReloadState',
  'TexReverseSearch',
  'TexStatus',
  'TexStatusAll',
  'TexStop',
  'TexStopAll',
  'TexToc',
  'TexTocToggle',
  'TexToggleMain',
  'TexView',
}

describe('plugin', function()
  after_each(H.cleanup)

  describe('commands', function()
    it('are all registered by the bootstrap', function()
      local registered = vim.api.nvim_get_commands({})
      for _, name in ipairs(COMMANDS) do
        T.ok(registered[name], ('missing command :%s'):format(name))
      end
    end)

    it('all carry a description', function()
      local registered = vim.api.nvim_get_commands({})
      for _, name in ipairs(COMMANDS) do
        T.ok(registered[name] and registered[name].definition ~= '', name)
      end
    end)

    it(':TexQfLevel cycles the quickfix level', function()
      local qf = require('nvim-tex.qf')
      qf.set_level('error')
      vim.cmd('TexQfLevel')
      T.eq('warning', qf.level())
    end)
  end)

  describe('attaching', function()
    it('sets the mappings and the LaTeX options on a tex buffer', function()
      local bufnr = H.buf({ '\\documentclass{article}' })
      local keymaps = vim.api.nvim_buf_get_keymap(bufnr, 'n')
      local lhss = vim.tbl_map(function(map)
        return map.lhs
      end, keymaps)
      T.contains(lhss, ']]')
      T.contains(lhss, ']m')
      T.contains(lhss, '%')
    end)

    it('sets the text object mappings', function()
      local bufnr = H.buf({ '\\documentclass{article}' })
      local lhss = vim.tbl_map(function(map)
        return map.lhs
      end, vim.api.nvim_buf_get_keymap(bufnr, 'x'))
      T.contains(lhss, 'ae')
      T.contains(lhss, 'ie')
      T.contains(lhss, 'a$')
      T.contains(lhss, 'aP')
    end)

    it('fires the NvimTexAttach autocmd', function()
      local seen = nil
      vim.api.nvim_create_autocmd('User', {
        pattern = 'NvimTexAttach',
        once = true,
        callback = function(args)
          seen = args.data.bufnr
        end,
      })
      local bufnr = H.buf({ 'text' })
      T.eq(bufnr, seen)
    end)

    it('leaves a buffer of another filetype alone', function()
      local bufnr = H.buf({ 'print("hi")' }, { filetype = 'lua' })
      local lhss = vim.tbl_map(function(map)
        return map.lhs
      end, vim.api.nvim_buf_get_keymap(bufnr, 'n'))
      T.excludes(lhss, ']m')
    end)

    it('skips the mapping groups that were turned off', function()
      config.setup({ mappings = { motions = false } })
      local bufnr = H.buf({ 'text' })
      nvim_tex.attach(bufnr)
      local lhss = vim.tbl_map(function(map)
        return map.lhs
      end, vim.api.nvim_buf_get_keymap(bufnr, 'n'))
      T.excludes(lhss, ']m')
    end)
  end)

  describe('setup', function()
    it('applies the options and stays callable twice', function()
      nvim_tex.setup({ qf = { height = 12 } })
      T.eq(12, config.get('qf', 'height'))
      nvim_tex.setup({})
      T.eq(8, config.get('qf', 'height'))
    end)
  end)

  describe('health', function()
    it('runs through without raising', function()
      local checked = {}
      local health = vim.health
      -- `vim.health.*` only works inside a real `:checkhealth` buffer.
      vim.health = setmetatable({}, {
        __index = function(_, key)
          return function(...)
            checked[#checked + 1] = { key, ... }
          end
        end,
      })
      local ok, err = pcall(require('nvim-tex.health').check)
      vim.health = health
      T.ok(ok, tostring(err))
      T.ok(#checked > 0)
    end)
  end)
end)
