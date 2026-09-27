--- tectonic backend.
---
--- Tectonic reruns TeX and BibTeX on its own, so a single invocation gives a
--- finished PDF. What it lacks is a watch mode for a plain `.tex` file --
--- `tectonic -X watch` needs a `Tectonic.toml` workspace -- so the backend is
--- single shot only: it has no `is_finished_line` to end a watch cycle.
local config = require('nvim-tex.config')
local project_mod = require('nvim-tex.project')
local util = require('nvim-tex.util')

local M = {
  name = 'tectonic',
  install_hint = 'Install tectonic: https://tectonic-typesetting.github.io',
}

--- Files tectonic leaves behind: the log and SyncTeX data from the default
--- options, the rest only with `--keep-intermediates`.
local CLEAN_EXT = { 'log', 'synctex.gz', 'aux', 'bbl', 'blg', 'out', 'toc', 'lof', 'lot', 'nav', 'snm', 'vrb' }

---@param project table
---@param opts table|nil `{ target = string }`
---@return string[] cmd
function M.build_cmd(project, opts)
  opts = opts or {}
  local tectonic = config.get('compiler', 'tectonic')
  local target = opts.target or project.main

  local cmd = util.as_cmd(tectonic.executable)
  vim.list_extend(cmd, tectonic.options or {})
  if project.out_dir_set then
    -- Unlike latexmk, tectonic refuses an output directory that is missing.
    util.mkdir(project.out_dir)
    vim.list_extend(cmd, { '--outdir', project.out_dir })
  end
  -- Tectonic resolves `\input` against the directory of the file it compiles,
  -- not against the working directory. A target outside the project root --
  -- the fragment `:TexCompileSelected` writes to the cache -- would lose its
  -- relative includes without this.
  if util.normalize(vim.fs.dirname(target)) ~= util.normalize(project.root) then
    vim.list_extend(cmd, { '-Z', 'search-path=' .. project.root })
  end

  cmd[#cmd + 1] = target
  return cmd
end

--- Tectonic has no clean command of its own; these are the files to delete.
---@param project table
---@param full boolean also remove the PDF
---@return string[]
function M.clean_files(project, full)
  local tectonic = config.get('compiler', 'tectonic')
  local exts = vim.list_extend({}, CLEAN_EXT)
  vim.list_extend(exts, vim.split(tectonic.clean_ext or '', '%s+', { trimempty = true }))
  if full then
    exts[#exts + 1] = 'pdf'
  end

  local files = {}
  for _, ext in ipairs(exts) do
    local path = project_mod.output_file(project, ext)
    if util.is_file(path) then
      files[#files + 1] = path
    end
  end
  return files
end

--- Did tectonic report a failure on this line? The exit code says as much for
--- a single shot run; this keeps the status right should a wrapper swallow it.
---@param line string
---@return boolean
function M.is_failure_line(line)
  return line:match('^error: ') ~= nil
end

return M
