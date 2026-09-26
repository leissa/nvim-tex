--- A minimal test runner.
---
--- nvim-tex has no runtime dependencies and the test suite adds none: this
--- file is the whole framework. Spec files get `describe`, `it`,
--- `before_each` and `after_each` as globals, plus the assertion table `T`,
--- and `M.main` runs them and exits with a non-zero status on failure.
local M = {}

local NO_COLOR = os.getenv('NO_COLOR') ~= nil

---@param code string
---@param text string
---@return string
local function paint(code, text)
  if NO_COLOR then
    return text
  end
  return ('\27[%sm%s\27[0m'):format(code, text)
end

local function red(s)
  return paint('31', s)
end
local function green(s)
  return paint('32', s)
end
local function yellow(s)
  return paint('33', s)
end
local function dim(s)
  return paint('90', s)
end
local function bold(s)
  return paint('1', s)
end

local function out(text)
  io.stdout:write(text)
  io.stdout:flush()
end

--------------------------------------------------------------------------- --
-- Assertions
--------------------------------------------------------------------------- --

--- Thrown by `T.skip`; recognised by the handler in `run_test`.
local SKIP = {}

---@param value any
---@return string
local function show(value)
  if type(value) == 'string' then
    return ('%q'):format(value)
  end
  return vim.inspect(value)
end

---@param message string
local function fail(message)
  error({ __assertion = true, message = message }, 3)
end

T = {}

--- Deep equality.
---@param expected any
---@param actual any
---@param context string|nil
function T.eq(expected, actual, context)
  if not vim.deep_equal(expected, actual) then
    fail(('%sexpected %s\n     got %s'):format(context and (context .. ': ') or '', show(expected), show(actual)))
  end
end

---@param unexpected any
---@param actual any
function T.neq(unexpected, actual, context)
  if vim.deep_equal(unexpected, actual) then
    fail(('%sexpected something other than %s'):format(context and (context .. ': ') or '', show(unexpected)))
  end
end

--- Truthy.
---@param value any
---@param context string|nil
function T.ok(value, context)
  if not value then
    fail(('%sexpected a truthy value, got %s'):format(context and (context .. ': ') or '', show(value)))
  end
end

--- Falsy (`false` or `nil`).
---@param value any
---@param context string|nil
function T.falsy(value, context)
  if value then
    fail(('%sexpected a falsy value, got %s'):format(context and (context .. ': ') or '', show(value)))
  end
end

--- `string.match` against a Lua pattern.
---@param pattern string
---@param actual string
function T.matches(pattern, actual)
  if type(actual) ~= 'string' or not actual:match(pattern) then
    fail(('expected a string matching %s\n     got %s'):format(show(pattern), show(actual)))
  end
end

--- `list` contains `value` (deep equality).
---@param list any[]
---@param value any
function T.contains(list, value)
  for _, item in ipairs(list) do
    if vim.deep_equal(item, value) then
      return
    end
  end
  fail(('expected %s to contain %s'):format(show(list), show(value)))
end

---@param list any[]
---@param value any
function T.excludes(list, value)
  for _, item in ipairs(list) do
    if vim.deep_equal(item, value) then
      fail(('expected %s not to contain %s'):format(show(list), show(value)))
    end
  end
end

--- `fn` raises, and the error matches `pattern` when one is given.
---@param fn function
---@param pattern string|nil
function T.raises(fn, pattern)
  local ok, err = pcall(fn)
  if ok then
    fail('expected an error, but the call succeeded')
  end
  if pattern and not tostring(err):match(pattern) then
    fail(('expected an error matching %s\n     got %s'):format(show(pattern), show(tostring(err))))
  end
end

--- Abandon the current test without failing it.
---@param reason string
function T.skip(reason)
  error(setmetatable({ reason = reason }, SKIP), 2)
end

--------------------------------------------------------------------------- --
-- Collection and execution
--------------------------------------------------------------------------- --

local state = {
  names = {},
  before = {},
  after = {},
  pass = 0,
  fail = 0,
  skip = 0,
  failures = {},
}

---@param name string
---@return string
local function full_name(name)
  local parts = vim.list_extend({}, state.names)
  parts[#parts + 1] = name
  return table.concat(parts, ' › ')
end

---@param err any
---@return table
local function handler(err)
  if type(err) == 'table' and getmetatable(err) == SKIP then
    return err
  end
  if type(err) == 'table' and err.__assertion then
    return { message = err.message, traceback = debug.traceback('', 2) }
  end
  return { message = tostring(err), traceback = debug.traceback('', 2) }
end

---@param name string
---@param fn function
function _G.describe(name, fn)
  state.names[#state.names + 1] = name
  state.before[#state.before + 1] = {}
  state.after[#state.after + 1] = {}

  local ok, err = xpcall(fn, handler)
  if not ok then
    state.fail = state.fail + 1
    state.failures[#state.failures + 1] = {
      name = table.concat(state.names, ' › ') .. ' (while collecting)',
      message = err.message,
      traceback = err.traceback,
    }
  end

  table.remove(state.names)
  table.remove(state.before)
  table.remove(state.after)
end

---@param fn function
function _G.before_each(fn)
  local list = state.before[#state.before]
  assert(list, 'before_each outside of a describe block')
  list[#list + 1] = fn
end

---@param fn function
function _G.after_each(fn)
  local list = state.after[#state.after]
  assert(list, 'after_each outside of a describe block')
  list[#list + 1] = fn
end

---@param name string
---@param fn function
function _G.it(name, fn)
  local label = full_name(name)

  local ok, err = xpcall(function()
    for _, list in ipairs(state.before) do
      for _, hook in ipairs(list) do
        hook()
      end
    end
    fn()
  end, handler)

  -- Teardown runs innermost first, and always.
  for i = #state.after, 1, -1 do
    for _, hook in ipairs(state.after[i]) do
      pcall(hook)
    end
  end

  if ok then
    state.pass = state.pass + 1
    out(green('  ✓ ') .. dim(label) .. '\n')
  elseif getmetatable(err) == SKIP then
    state.skip = state.skip + 1
    out(yellow('  ~ ') .. dim(label) .. yellow(' — ' .. err.reason) .. '\n')
  else
    state.fail = state.fail + 1
    state.failures[#state.failures + 1] = {
      name = label,
      message = err.message,
      traceback = err.traceback,
    }
    out(red('  ✗ ') .. label .. '\n')
  end
end

--- Spec files to run: the basenames in `$SPEC` if it is set -- `SPEC='qf toc'`
--- selects `tests/qf_spec.lua` and `tests/toc_spec.lua` -- every
--- `tests/*_spec.lua` otherwise.
---@return string[]
local function spec_files()
  local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
  local selected = os.getenv('SPEC')
  if selected and selected ~= '' then
    return vim.tbl_map(function(name)
      return ('%s/%s_spec.lua'):format(root, name)
    end, vim.split(selected, '%s+', { trimempty = true }))
  end
  local found = vim.fn.glob(root .. '/*_spec.lua', false, true)
  table.sort(found)
  return found
end

--- Run every spec file and exit with the appropriate status.
function M.main()
  local files = spec_files()
  local started = vim.uv.hrtime()

  for _, file in ipairs(files) do
    out(bold('\n' .. vim.fn.fnamemodify(file, ':t')) .. '\n')
    local chunk, load_err = loadfile(file)
    if not chunk then
      state.fail = state.fail + 1
      state.failures[#state.failures + 1] = { name = file, message = load_err or 'load failed' }
      out(red('  ✗ could not load: ') .. tostring(load_err) .. '\n')
    else
      local ok, err = xpcall(chunk, handler)
      if not ok then
        state.fail = state.fail + 1
        state.failures[#state.failures + 1] = {
          name = file,
          message = err.message,
          traceback = err.traceback,
        }
        out(red('  ✗ ') .. tostring(err.message) .. '\n')
      end
    end
  end

  local elapsed = (vim.uv.hrtime() - started) / 1e6

  if #state.failures > 0 then
    out(bold('\nFailures\n'))
    for _, failure in ipairs(state.failures) do
      out('\n' .. red('✗ ' .. failure.name) .. '\n')
      for _, line in ipairs(vim.split(failure.message, '\n', { plain = true })) do
        out('    ' .. line .. '\n')
      end
      if failure.traceback then
        out(dim(failure.traceback:gsub('\n', '\n    ')) .. '\n')
      end
    end
  end

  local summary = ('\n%d passed, %d failed, %d skipped  (%.0f ms)\n'):format(
    state.pass,
    state.fail,
    state.skip,
    elapsed
  )
  out(state.fail > 0 and red(summary) or green(summary))

  os.exit(state.fail > 0 and 1 or 0)
end

return M
