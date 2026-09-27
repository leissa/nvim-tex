--- Word and letter counts through `texcount` (VimTeX's `:VimtexCountWords`).
---
--- The whole document is counted from the files on disk, with `\input` and
--- `\include` followed (`-merge`, or `-inc` for the per-file report). A range
--- is fed to texcount on stdin, with `-dir` pointing at the project root so
--- that includes in it still resolve.
local config = require('nvim-tex.config')
local project_mod = require('nvim-tex.project')
local util = require('nvim-tex.util')

local M = {}

--- Build the texcount command line.
---@param project table
---@param opts table `{ letters = boolean, detailed = boolean, stdin = boolean }`
---@return string[]
function M.build_cmd(project, opts)
  local texcount = config.get('texcount')
  local cmd = util.as_cmd(texcount.executable)
  -- `-nosub` drops the per-section breakdown; `-sum` adds up text, headers,
  -- captions and math the way a word count is usually meant.
  vim.list_extend(cmd, { '-nosub', '-sum' })
  if opts.letters then
    cmd[#cmd + 1] = '-letter'
  end
  if opts.detailed and not opts.stdin then
    cmd[#cmd + 1] = '-inc'
  else
    cmd[#cmd + 1] = '-merge'
  end
  if not opts.detailed then
    -- Just the number.
    vim.list_extend(cmd, { '-q', '-1' })
  end
  vim.list_extend(cmd, texcount.options or {})
  if opts.stdin then
    vim.list_extend(cmd, { '-dir=' .. project.root, '-' })
  else
    cmd[#cmd + 1] = project.main
  end
  return cmd
end

--- texcount exits 0 even when it could not read a file. It says so on
--- stderr, with an `(errors:N)` tally after the count on stdout.
---@param stdout string[]
---@param stderr string[]
---@return string[]
function M.errors(stdout, stderr)
  local out = {}
  for _, line in ipairs(stderr) do
    local err = line:match('^ERROR:%s*(.*)$')
    if err then
      out[#out + 1] = err
    end
  end
  if #out == 0 then
    for _, line in ipairs(stdout) do
      if line:match('%(errors:%d+%)') then
        out[#out + 1] = vim.trim(line)
      end
    end
  end
  return out
end

--- The number in a brief (`-1`) report.
---@param lines string[]
---@return integer|nil
function M.parse_brief(lines)
  for _, line in ipairs(lines) do
    local n = line:match('^%s*(%d+)%s*$')
    if n then
      return tonumber(n)
    end
  end
  return nil
end

---@param project table
---@return boolean
local function has_unsaved(project)
  for _, bufnr in ipairs(project_mod.buffers(project)) do
    if vim.bo[bufnr].modified then
      return true
    end
  end
  return false
end

--- Count the words (or letters) of `project`, or of `lines` when given.
---@param project table
---@param opts table|nil `{ letters = boolean, detailed = boolean, lines = string[] }`
function M.count(project, opts)
  opts = opts or {}
  local stdin = opts.lines ~= nil
  local cmd = M.build_cmd(project, { letters = opts.letters, detailed = opts.detailed, stdin = stdin })
  if not util.executable(cmd[1]) then
    util.error(("'%s' is not executable; texcount ships with TeX Live and MiKTeX"):format(cmd[1]))
    return
  end

  local unit = opts.letters and 'letters' or 'words'
  local what = stdin and 'selection' or vim.fn.fnamemodify(project.main, ':t')
  -- Only the files on disk are read. A selection is sent as it stands.
  local unsaved = not stdin and has_unsaved(project)

  vim.system(cmd, {
    cwd = project.root,
    text = true,
    stdin = stdin and (table.concat(opts.lines, '\n') .. '\n') or nil,
  }, function(result)
    vim.schedule(function()
      local lines = vim.split(result.stdout or '', '\n', { trimempty = true })
      local stderr = vim.split(result.stderr or '', '\n', { trimempty = true })
      local errors = M.errors(lines, stderr)
      if result.code ~= 0 or #errors > 0 then
        -- Only the ERROR lines, if any: newer Perls also warn about
        -- texcount's own source on every run.
        local detail = #errors > 0 and table.concat(errors, '; ') or table.concat(stderr, ' ')
        util.error('texcount failed: ' .. detail)
        return
      end

      if opts.detailed then
        util.scratch('nvim-tex://texcount', lines, { height = math.min(#lines, 20) })
        if unsaved then
          util.warn('unsaved changes are not counted')
        end
        return
      end

      local n = M.parse_brief(lines)
      if not n then
        util.error('could not read the texcount output: ' .. table.concat(lines, ' '))
        return
      end
      local note = unsaved and ' (unsaved changes are not counted)' or ''
      util.info(('%s: %d %s%s'):format(what, n, unit, note))
    end)
  end)
end

return M
