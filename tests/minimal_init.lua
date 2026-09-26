-- Minimal init for the test suite: the plugin, the tests and nothing else.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

vim.opt.runtimepath:prepend(root)
package.path = table.concat({ root .. '/?.lua', root .. '/?/init.lua', package.path }, ';')

-- Find a `latex` parser without putting anything else on the runtimepath: the
-- one `make parser` (and CI) builds, or one a `:TSInstall latex` left behind.
-- Specs that need it skip when there is none.
local candidates = {
  root .. '/.deps/parser/latex.so',
  vim.fs.joinpath(vim.fn.stdpath('data'), 'site', 'parser', 'latex.so'),
}
if vim.env.NVIM_TEX_LATEX_PARSER then
  table.insert(candidates, 1, vim.env.NVIM_TEX_LATEX_PARSER)
end
for _, candidate in ipairs(candidates) do
  if vim.fn.filereadable(candidate) == 1 then
    pcall(vim.treesitter.language.add, 'latex', { path = candidate })
    break
  end
end

vim.opt.swapfile = false
vim.opt.shadafile = 'NONE'
vim.opt.more = false
vim.g.mapleader = ' '
vim.g.maplocalleader = ','

_G.NVIM_TEX_ROOT = root
