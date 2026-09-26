--- latexmk backend.
---
--- Produces the command lines; the job plumbing lives in `nvim-tex.compiler`.
local config = require('nvim-tex.config')
local util = require('nvim-tex.util')

local M = { name = 'latexmk' }

---@param project table
---@return string[]
local function engine_flags(project)
  local latexmk = config.get('compiler', 'latexmk')
  local program = project.tex_program and project.tex_program:lower() or nil
  local engine = program and latexmk.engines[program] or latexmk.engines['_']
  if not engine or engine == '' then
    return {}
  end
  return vim.split(engine, '%s+', { trimempty = true })
end

--- Directory flags. `-auxdir` needs `-emulate-aux-dir` to work with the
--- LaTeX engines that do not support a separate aux directory natively.
---@param project table
---@return string[]
local function dir_flags(project)
  local flags = {}
  if project.out_dir_set then
    util.mkdir(project.out_dir)
    flags[#flags + 1] = '-outdir=' .. project.out_dir
  end
  if project.aux_dir_set then
    util.mkdir(project.aux_dir)
    flags[#flags + 1] = '-auxdir=' .. project.aux_dir
    flags[#flags + 1] = '-emulate-aux-dir'
  end
  return flags
end

--- @param project table
--- @param opts table|nil `{ continuous = boolean, target = string }`
--- @return string[] cmd
function M.build_cmd(project, opts)
  opts = opts or {}
  local latexmk = config.get('compiler', 'latexmk')

  local cmd = util.as_cmd(latexmk.executable)
  vim.list_extend(cmd, engine_flags(project))
  vim.list_extend(cmd, latexmk.options or {})
  vim.list_extend(cmd, dir_flags(project))

  local continuous = opts.continuous
  if continuous == nil then
    continuous = latexmk.continuous
  end
  if continuous then
    -- `-view=none` keeps latexmk from spawning its own viewer; nvim-tex owns
    -- the viewer so that forward search has a handle to talk to.
    vim.list_extend(cmd, { '-pvc', '-view=none' })
  end

  cmd[#cmd + 1] = opts.target or project.main
  return cmd
end

---@param project table
---@param full boolean also remove the final PDF (`latexmk -C`)
---@return string[]
function M.clean_cmd(project, full)
  local latexmk = config.get('compiler', 'latexmk')
  local cmd = util.as_cmd(latexmk.executable)
  vim.list_extend(cmd, dir_flags(project))
  if latexmk.clean_ext and latexmk.clean_ext ~= '' then
    cmd[#cmd + 1] = '-e'
    cmd[#cmd + 1] = "$clean_ext = '" .. latexmk.clean_ext .. "'"
  end
  cmd[#cmd + 1] = full and '-C' or '-c'
  cmd[#cmd + 1] = project.main
  return cmd
end

--- End of one compilation cycle in continuous mode.
---
--- `-pvc` prints this marker after every build, including the first one and
--- the ones where nothing had to be redone. It is the only line that reliably
--- separates one cycle from the next.
---@param line string
---@return boolean
function M.is_finished_line(line)
  return line:match('^=== Watching for updated files') ~= nil
end

--- Start of a compilation cycle.
---@param line string
---@return boolean
function M.is_started_line(line)
  return line:match("^Latexmk: Run number %d+ of rule") ~= nil
    or line:match('^Latexmk: applying rule') ~= nil
end

--- Did latexmk report a failure on this line?
---@param line string
---@return boolean
function M.is_failure_line(line)
  return line:match('^Latexmk: Errors, so I did not finish') ~= nil
    or line:match('^Latexmk: Failure') ~= nil
    or line:match('^Latexmk: Did not finish processing file') ~= nil
end

return M
