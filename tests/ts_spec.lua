local H = require('tests.helpers')
local ts = require('nvim-tex.ts')

--- Is the cursor position marked by `|` in `text` inside a math zone?
---@param text string
---@return boolean
local function in_math_at_marker(text)
  local lines = vim.split(text, '\n', { plain = true })
  local row, col
  for index, line in ipairs(lines) do
    local at = line:find('|', 1, true)
    if at then
      row, col = index, at - 1
      lines[index] = line:gsub('|', '', 1)
      break
    end
  end
  assert(row, 'the fixture needs a | to mark the cursor')

  local bufnr = H.buf(lines)
  return ts.in_math(bufnr, { row, col })
end

describe('ts', function()
  before_each(H.need_parser)
  after_each(H.cleanup)

  describe('in_math', function()
    it('is false in running text', function()
      T.falsy(in_math_at_marker('Some pro|se here.'))
    end)

    it('is true inside $ ... $', function()
      T.ok(in_math_at_marker('Text $x + |y$ more text.'))
    end)

    it('is false after the closing $', function()
      T.falsy(in_math_at_marker('Text $x + y$ mo|re text.'))
    end)

    it('is true inside \\( ... \\)', function()
      T.ok(in_math_at_marker('Text \\(x + |y\\) more.'))
    end)

    it('is true inside \\[ ... \\]', function()
      T.ok(in_math_at_marker('\\[\n  x + |y\n\\]'))
    end)

    it('is true inside an equation environment', function()
      T.ok(in_math_at_marker('\\begin{equation}\n  E = m|c^2\n\\end{equation}'))
    end)

    it('is true inside align*', function()
      T.ok(in_math_at_marker('\\begin{align*}\n  a &= |b\n\\end{align*}'))
    end)

    it('is false inside a non-math environment', function()
      T.falsy(in_math_at_marker('\\begin{itemize}\n  \\item o|ne\n\\end{itemize}'))
    end)

    it('is true in a formula whose closing delimiter is not typed yet', function()
      T.ok(in_math_at_marker('Text $x + |'))
    end)

    it('is true in a math environment whose \\end is not typed yet', function()
      T.ok(in_math_at_marker('\\begin{equation}\n  x + |'))
    end)

    it('is false after an escaped dollar sign', function()
      T.falsy(in_math_at_marker('Costs \\$5 and mo|re.'))
    end)

    it('is false in a comment', function()
      T.falsy(in_math_at_marker('% $x$ is ma|th in the prose'))
    end)
  end)

  describe('env_name', function()
    it('reads the name off a \\begin', function()
      local bufnr = H.buf({ '\\begin{itemize}', '\\item one', '\\end{itemize}' })
      local node = ts.collect(bufnr, ts.ENVIRONMENT)[1]
      T.ok(node)
      T.eq('itemize', ts.env_name(node, bufnr))
    end)

    it('keeps the star', function()
      local bufnr = H.buf({ '\\begin{align*}', 'a &= b', '\\end{align*}' })
      local node = ts.collect(bufnr, ts.ENVIRONMENT)[1]
      T.eq('align*', ts.env_name(node, bufnr))
    end)

    it('is nil for a node that is not an environment', function()
      local bufnr = H.buf({ '\\textbf{x}' })
      T.eq(nil, ts.env_name(ts.root(bufnr), bufnr))
    end)
  end)

  describe('collect', function()
    it('finds every environment in document order', function()
      local bufnr = H.buf({
        '\\begin{itemize}',
        '\\item one',
        '\\end{itemize}',
        '\\begin{equation}',
        'x = y',
        '\\end{equation}',
      })
      local names = vim.tbl_map(function(node)
        return ts.env_name(node, bufnr)
      end, ts.collect(bufnr, ts.ENVIRONMENT))
      T.eq({ 'itemize', 'equation' }, names)
    end)

    it('finds nested environments too', function()
      local bufnr = H.buf({
        '\\begin{figure}',
        '\\begin{center}',
        'x',
        '\\end{center}',
        '\\end{figure}',
      })
      T.eq(2, #ts.collect(bufnr, ts.ENVIRONMENT))
    end)

    it('accepts a predicate instead of a type set', function()
      local bufnr = H.buf({
        '\\begin{frame}',
        '\\end{frame}',
        '\\begin{itemize}',
        '\\item a',
        '\\end{itemize}',
      })
      local frames = ts.collect(bufnr, function(node)
        return ts.ENVIRONMENT[node:type()] and ts.env_name(node, bufnr) == 'frame'
      end)
      T.eq(1, #frames)
    end)

    it('finds the sectioning commands', function()
      local bufnr = H.buf({
        '\\section{One}',
        'text',
        '\\subsection{Two}',
        'text',
      })
      T.eq(2, #ts.collect(bufnr, ts.SECTION))
    end)
  end)

  describe('ancestor', function()
    it('walks up to the enclosing environment', function()
      local bufnr = H.buf({ '\\begin{itemize}', '\\item one', '\\end{itemize}' })
      H.cursor(2, 8)
      local node = ts.node_at_cursor(bufnr)
      T.ok(node)
      local env = ts.ancestor(node, ts.ENVIRONMENT)
      T.ok(env)
      T.eq('itemize', ts.env_name(env, bufnr))
    end)

    it('is nil when nothing matches', function()
      local bufnr = H.buf({ 'plain prose' })
      H.cursor(1, 3)
      T.eq(nil, ts.ancestor(ts.node_at_cursor(bufnr), ts.ENVIRONMENT))
    end)
  end)

  describe('range and contains', function()
    it('reports an end-inclusive 1-indexed range', function()
      local bufnr = H.buf({ 'a \\textbf{bold} b' })
      local node = ts.collect(bufnr, function(n)
        return n:type() == 'generic_command'
      end)[1]
      T.ok(node)
      local sr, sc, er, ec = ts.range(node)
      T.eq(1, sr)
      T.eq(2, sc)
      T.eq(1, er)
      T.eq(14, ec) -- the closing brace of \textbf{bold}
    end)

    it('knows which positions a node covers', function()
      local bufnr = H.buf({ 'a \\textbf{bold} b' })
      local node = ts.collect(bufnr, function(n)
        return n:type() == 'generic_command'
      end)[1]
      T.ok(ts.contains(node, 1, 5))
      T.falsy(ts.contains(node, 1, 0))
      T.falsy(ts.contains(node, 1, 16))
    end)
  end)

  describe('is_command', function()
    it('accepts a generic command', function()
      local bufnr = H.buf({ '\\textbf{x}' })
      local node = ts.collect(bufnr, function(n)
        return n:type() == 'generic_command'
      end)[1]
      T.ok(ts.is_command(node))
    end)

    it('rejects a sectioning command', function()
      local bufnr = H.buf({ '\\section{One}' })
      local node = ts.collect(bufnr, ts.SECTION)[1]
      T.ok(node)
      T.falsy(ts.is_command(node))
    end)
  end)
end)
