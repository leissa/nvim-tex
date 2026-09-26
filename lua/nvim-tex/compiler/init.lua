--- Compiler job management.
---
--- One job per project. In continuous mode the job outlives the command that
--- started it and keeps rebuilding; `compile` therefore toggles.
local config = require('nvim-tex.config')
local project_mod = require('nvim-tex.project')
local qf = require('nvim-tex.qf')
local util = require('nvim-tex.util')

local M = {}

M.backends = {
  latexmk = require('nvim-tex.compiler.latexmk'),
}

---@return table|nil
function M.backend()
  local method = config.get('compiler', 'method')
  local backend = M.backends[method]
  if not backend then
    util.error(("unknown compiler method '%s'"):format(tostring(method)))
  end
  return backend
end

--- Fire a `User NvimTex<name>` autocmd.
---
--- Only plain data is passed along; the project itself holds job handles,
--- which cannot cross the autocmd boundary. Look it up with
--- `require('nvim-tex.project').projects[data.main]`.
---@param name string
---@param project table
local function emit(name, project)
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'NvimTex' .. name,
    data = { main = project.main, root = project.root, status = project.last_status },
  })
end

---@param project table
---@return boolean
function M.is_running(project)
  return project.compiler ~= nil and project.compiler.handle ~= nil
end

--- Split incoming chunks into complete lines.
---@param state table
---@param chunk string|nil
---@param on_line fun(line: string)
local function feed(state, chunk, on_line)
  if not chunk or chunk == '' then
    return
  end
  state.partial = (state.partial or '') .. chunk
  while true do
    local nl = state.partial:find('\n')
    if not nl then
      break
    end
    local line = state.partial:sub(1, nl - 1):gsub('\r$', '')
    state.partial = state.partial:sub(nl + 1)
    on_line(line)
  end
end

--- Report the result of one compilation run.
---@param project table
---@param code integer|nil exit code, nil when running continuously
---@param saw_failure boolean|nil latexmk reported an error in its output
local function finish_run(project, code, saw_failure)
  local errors, warnings = qf.update(project, { silent = true })
  local silent = config.get('compiler', 'silent')

  local failed = (code ~= nil and code ~= 0) or errors > 0 or saw_failure == true
  project.last_status = failed and 'failed' or 'success'

  -- Infos are deliberately left out of these counts: they are hidden from the
  -- quickfix list by default, so reporting them would only add noise of its
  -- own. `:TexStatus` shows the full breakdown.
  if failed then
    util.info_unless(silent, ('compilation failed (%d errors, %d warnings)'):format(errors, warnings))
    emit('CompileFailed', project)
  else
    local detail = warnings > 0 and (' (%d warnings)'):format(warnings) or ''
    util.info_unless(silent, 'compilation succeeded' .. detail)
    emit('CompileSuccess', project)
  end
end

---@param project table
---@param opts table|nil `{ continuous = boolean, target = string, on_success = function }`
function M.start(project, opts)
  opts = opts or {}
  if not config.get('compiler', 'enabled') then
    util.warn('compiler is disabled')
    return
  end
  if M.is_running(project) then
    util.info('compilation already running')
    return
  end

  local backend = M.backend()
  if not backend then
    return
  end

  local latexmk = config.get('compiler', 'latexmk')
  local continuous = opts.continuous
  if continuous == nil then
    continuous = latexmk.continuous
  end

  local cmd = backend.build_cmd(project, vim.tbl_extend('force', opts, { continuous = continuous }))
  if not util.executable(cmd[1]) then
    util.error(("'%s' is not executable"):format(cmd[1]))
    return
  end

  project.output = {}
  project.last_status = 'running'
  project.compiler = {
    cmd = cmd,
    continuous = continuous,
    started_at = os.time(),
    saw_failure = false,
    on_success = opts.on_success,
  }

  local state = {}
  local hooks = latexmk.hooks or {}

  local function on_line(line)
    project.output[#project.output + 1] = line
    if #project.output > 5000 then
      table.remove(project.output, 1)
    end

    for _, hook in ipairs(hooks) do
      pcall(hook, line)
    end

    if backend.is_failure_line and backend.is_failure_line(line) then
      project.compiler.saw_failure = true
    end
    if continuous and backend.is_finished_line and backend.is_finished_line(line) then
      finish_run(project, nil, project.compiler.saw_failure)
      project.compiler.saw_failure = false
      if project.compiler and project.compiler.on_success then
        local cb = project.compiler.on_success
        project.compiler.on_success = nil
        cb()
      end
    end
  end

  local function on_output(_, chunk)
    vim.schedule(function()
      feed(state, chunk, on_line)
    end)
  end

  local handle = vim.system(cmd, {
    cwd = project.root,
    text = true,
    -- A large `max_print_line` keeps TeX from wrapping paths in the log,
    -- which is what makes file attribution in the quickfix list work.
    env = vim.tbl_extend('force', { max_print_line = '2000' }, {}),
    stdout = on_output,
    stderr = on_output,
  }, function(result)
    vim.schedule(function()
      if state.partial and state.partial ~= '' then
        on_line(state.partial)
        state.partial = ''
      end
      local was_stopped = project.compiler and project.compiler.stopping
      local on_success = project.compiler and project.compiler.on_success
      local saw_failure = project.compiler and project.compiler.saw_failure
      project.compiler = nil
      if was_stopped then
        project.last_status = 'stopped'
        util.info_unless(config.get('compiler', 'silent'), 'compilation stopped')
      else
        finish_run(project, result.code, saw_failure)
        if on_success and project.last_status == 'success' then
          on_success()
        end
      end
      emit('CompileStopped', project)
    end)
  end)

  project.compiler.handle = handle
  emit('CompileStarted', project)

  local mode = continuous and 'continuous' or 'single shot'
  util.info_unless(config.get('compiler', 'silent'), ('compiling %s (%s)'):format(vim.fn.fnamemodify(project.main, ':t'), mode))
end

---@param project table
function M.stop(project)
  if not M.is_running(project) then
    util.info('no compilation running')
    return
  end
  project.compiler.stopping = true
  project.compiler.handle:kill('sigterm')
end

function M.stop_all()
  local count = 0
  for _, project in pairs(project_mod.projects) do
    if M.is_running(project) then
      project.compiler.stopping = true
      project.compiler.handle:kill('sigterm')
      count = count + 1
    end
  end
  util.info(('stopped %d compilation(s)'):format(count))
end

--- Toggle in continuous mode, run once otherwise.
---@param project table
---@param opts table|nil
function M.compile(project, opts)
  opts = opts or {}
  if M.is_running(project) then
    M.stop(project)
  else
    M.start(project, opts)
  end
end

--- Compile once, regardless of the `continuous` setting.
---@param project table
---@param opts table|nil
function M.compile_single_shot(project, opts)
  opts = vim.tbl_extend('force', opts or {}, { continuous = false })
  if M.is_running(project) then
    util.warn('a compilation is already running; stop it first')
    return
  end
  M.start(project, opts)
end

--- Compile a fragment (visual selection or motion) as a standalone document,
--- reusing the preamble of the main file.
---@param project table
---@param lines string[]
function M.compile_selected(project, lines)
  local main_lines = util.readlines(project.main)
  local preamble = {}
  for _, line in ipairs(main_lines) do
    if line:match('\\begin%s*{document}') then
      break
    end
    preamble[#preamble + 1] = line
  end
  if #preamble == 0 then
    util.error('could not read the preamble of ' .. project.main)
    return
  end

  local dir = project_mod.cache_dir(project)
  local target = util.join(dir, 'selected.tex')

  local document = vim.list_extend({}, preamble)
  document[#document + 1] = '\\begin{document}'
  vim.list_extend(document, lines)
  document[#document + 1] = '\\end{document}'
  util.writelines(target, document)

  -- The fragment is compiled in its own throwaway project so that it never
  -- disturbs the state or output files of the real document.
  local fragment = {
    main = target,
    root = project.root,
    name = 'selected',
    tex_program = project.tex_program,
    out_dir = dir,
    aux_dir = dir,
    out_dir_set = true,
    aux_dir_set = true,
    output = {},
  }
  project_mod.projects[target] = fragment

  M.start(fragment, {
    continuous = false,
    on_success = function()
      require('nvim-tex.viewer').view(fragment)
    end,
  })
end

---@param project table
---@param full boolean
function M.clean(project, full)
  local backend = M.backend()
  if not backend then
    return
  end
  local cmd = backend.clean_cmd(project, full)
  vim.system(cmd, { cwd = project.root, text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        util.info(full and 'cleaned all output files' or 'cleaned auxiliary files')
      else
        util.error('clean failed: ' .. (result.stderr or ''):gsub('%s+$', ''))
      end
    end)
  end)
end

--- One-line status summary.
---@param project table
---@return string
function M.status_line(project)
  local name = vim.fn.fnamemodify(project.main, ':~:.')
  if M.is_running(project) then
    local mode = project.compiler.continuous and 'continuous' or 'single shot'
    return ('%s: running (%s)'):format(name, mode)
  end
  return ('%s: %s'):format(name, project.last_status or 'not started')
end

--- Show the captured compiler output in a scratch split.
---@param project table
function M.show_output(project)
  local output = project.output or {}
  if #output == 0 then
    util.info('no compiler output yet')
    return
  end
  util.scratch('nvim-tex://output', output, { filetype = 'log', height = 15 })
end

return M
