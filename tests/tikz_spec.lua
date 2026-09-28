local H = require('tests.helpers')
local config = require('nvim-tex.config')
local tikz = require('nvim-tex.tikz')

--- The statements of the pictures in `lines`, as `kind: text`.
---@param lines string[]
---@return string[]
local function statements(lines)
  local bufnr = H.buf(lines)
  return vim.tbl_map(function(statement)
    local r = statement.range
    local text = table.concat(vim.api.nvim_buf_get_text(bufnr, r[1], r[2], r[3], r[4], {}), '\n')
    return statement.kind .. ': ' .. text
  end, tikz.all_statements(bufnr))
end

--- `lines` inside a `tikzpicture`.
---@param lines string[]
---@return string[]
local function picture(lines)
  local out = { '\\begin{tikzpicture}' }
  vim.list_extend(out, lines)
  out[#out + 1] = '\\end{tikzpicture}'
  return out
end

describe('tikz', function()
  before_each(H.need_parser)
  after_each(function()
    config.setup({})
    H.cleanup()
  end)

  it('ends a path at its ;', function()
    T.eq(
      { 'path: \\draw (a) -- (b);', 'path: \\node (c) at (1,1) {c};', 'path: \\path(a)--(b);', 'path: x;' },
      statements(picture({ '\\draw (a) -- (b);', '\\node (c) at (1,1) {c};', '\\path(a)--(b);x;' }))
    )
  end)

  it('ignores a ; in a group, math, options or a comment', function()
    T.eq(
      { 'path: \\node {$x;y$} node {a;b};', 'path: \\draw[a=b;c] (0,0) ;' },
      statements(picture({ '\\node {$x;y$} node {a;b}; % c;d', '\\draw[a=b;c] (0,0) ;' }))
    )
  end)

  it('runs a path over several lines', function()
    T.eq({ 'path: \\draw (a)\n  -- (b)\n  -- (c);' }, statements(picture({ '\\draw (a)', '  -- (b)', '  -- (c);' })))
  end)

  it('takes a loop with its body, and the statements in the body', function()
    T.eq(
      {
        'foreach: \\foreach \\i in {1,2} {\n  \\fill (\\i,0) circle (1pt);\n}',
        'path: \\fill (\\i,0) circle (1pt);',
        'path: \\foreach \\x/\\y [count=\\j] in {a/b} \\draw (\\x) -- (\\y);',
        'path: \\foreach \\i in {1,2} \\foreach \\j in {3} \\fill (\\i,\\j) circle (1pt);',
      },
      statements(picture({
        '\\foreach \\i in {1,2} {',
        '  \\fill (\\i,0) circle (1pt);',
        '}',
        '\\foreach \\x/\\y [count=\\j] in {a/b} \\draw (\\x) -- (\\y);',
        '\\foreach \\i in {1,2} \\foreach \\j in {3} \\fill (\\i,\\j) circle (1pt);',
      }))
    )
  end)

  it('reads a command with its arguments as a statement of its own', function()
    T.eq(
      {
        'command: \\tikzset{a/.style={b}}',
        'command: \\pgfmathsetmacro{\\x}{1}',
        'command: \\def\\y{2}',
        'command: \\tikzstyle{q}=[r]',
        'path: \\edge{a}{b};',
        'path: \\draw (a);',
      },
      statements(picture({
        '\\tikzset{a/.style={b}}',
        '\\pgfmathsetmacro{\\x}{1}',
        '\\def\\y{2}',
        '\\tikzstyle{q}=[r]',
        '\\edge{a}{b};',
        '\\draw (a);',
      }))
    )
  end)

  it('scans scopes and nested environments', function()
    T.eq(
      { 'path: \\draw (a);', 'path: \\draw (b);' },
      statements(picture({ '\\begin{scope}[x=1]', '\\draw (a);', '\\end{scope}', '{ \\draw (b); }' }))
    )
  end)

  it('lets a path without its ; reach to the end of the picture', function()
    local bufnr = H.buf(picture({ '\\draw (a) -- (b);', '\\draw (a)', '' }))
    local statement = tikz.statement_at(bufnr, 3, 0, { reach = true })
    T.ok(statement)
    T.eq({ 2, 0, 2, 9 }, statement.range)
    T.eq(nil, tikz.statement_at(bufnr, 3, 0))
  end)

  it('finds the innermost statement at a position', function()
    local bufnr = H.buf(picture({ '\\foreach \\i in {1,2} {', '  \\fill (\\i,0);', '}' }))
    T.eq('path', tikz.statement_at(bufnr, 2, 4).kind)
    T.eq('foreach', tikz.statement_at(bufnr, 1, 0).kind)
  end)

  it('only reads the configured environments', function()
    local lines = { '\\begin{center}', '\\draw (a);', '\\end{center}' }
    T.eq({}, statements(lines))
    config.setup({ tikz = { environments = { 'center' } } })
    T.eq({ 'path: \\draw (a);' }, statements(lines))
  end)
end)
