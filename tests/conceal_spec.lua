local H = require('tests.helpers')
local conceal = require('nvim-tex.conceal')
local config = require('nvim-tex.config')

--- Each line of `lines` as it shows with 'conceallevel' at 2: concealed
--- ranges replaced by their character, styled ones marked `*like this*`.
---@param lines string|string[]
---@param opts table|nil `conceal` configuration
---@return string|string[]
local function shown(lines, opts)
  if opts then
    config.setup({ conceal = opts })
  end
  local single = type(lines) == 'string'
  lines = single and { lines } or lines
  local bufnr = H.buf(lines)
  local rows = conceal.items(bufnr, 0, #lines)
  local out = {}
  for row, line in ipairs(lines) do
    local items = rows[row - 1] or {}
    table.sort(items, function(a, b)
      return a.col < b.col
    end)
    local text, pos = {}, 0
    for _, item in ipairs(items) do
      text[#text + 1] = line:sub(pos + 1, item.col)
      local body = line:sub(item.col + 1, item.end_col)
      if item.hl then
        text[#text + 1] = '*' .. body .. '*'
      else
        text[#text + 1] = item.text
      end
      pos = item.end_col
    end
    text[#text + 1] = line:sub(pos + 1)
    out[row] = table.concat(text)
  end
  return single and out[1] or out
end

describe('conceal', function()
  before_each(H.need_parser)
  after_each(H.cleanup)

  describe('in math', function()
    it('shows Greek letters and symbols', function()
      T.eq('$α ≤ β → ∞$', shown('$\\alpha \\leq \\beta \\to \\infty$'))
    end)

    it('leaves the same commands alone in text and comments', function()
      T.eq('\\alpha and \\leq % $\\beta$', shown('\\alpha and \\leq % $\\beta$'))
    end)

    it('shows blackboard, calligraphic and fraktur letters', function()
      T.eq('$x ∈ ℝ, 𝒜, 𝔤$', shown('$x \\in \\mathbb{R}, \\mathcal{A}, \\mathfrak{g}$'))
    end)

    it('leaves a font command with more than a letter alone', function()
      T.eq('$\\mathbb{RR}$', shown('$\\mathbb{RR}$'))
    end)

    it('turns super- and subscripts into their Unicode forms', function()
      T.eq('$x² + y₁₂ + aⁿ$', shown('$x^2 + y_{12} + a^n$'))
    end)

    it('keeps a script that has a character without a Unicode form', function()
      T.eq('$x^{q} + y_{\\alpha}$', shown('$x^{q} + y_{\\alpha}$', { greek = false }))
    end)

    it('does not touch ^ and _ outside math', function()
      T.eq('file_name x^2', shown('file_name x^2'))
    end)

    it('hides \\left, \\right and the sizing commands', function()
      T.eq('\\[ (a) [b] \\]', shown('\\[ \\left(a\\right) \\bigl[b\\bigr] \\]'))
    end)

    it('hides the dot of \\left. and \\right.', function()
      T.eq('$ a| $', shown('$\\left. a\\right| $'))
    end)

    it('shows escaped braces', function()
      T.eq('$ { x ∣ x > 0 } $', shown('$ \\{ x \\mid x > 0 \\} $'))
    end)
  end)

  describe('in text', function()
    it('composes accents, braced or not', function()
      T.eq('café naïve garçon Ångström', shown('caf\\\'e na\\"{i}ve gar\\c{c}on \\AA{}ngstr\\"om'))
    end)

    it('shows single-character commands', function()
      T.eq('Straße … §2', shown('Stra\\ss{}e \\dots{} \\S2'))
    end)

    it('shows dashes and quotes', function()
      T.eq('1–2, a — b, “quoted”', shown("1--2, a --- b, ``quoted''"))
    end)

    it('leaves a single hyphen and dashes in math alone', function()
      T.eq('well-known $a--b$', shown('well-known $a--b$'))
    end)

    it('styles the argument of \\textbf and \\emph and hides the command', function()
      T.eq('a *bold* and *em* word', shown('a \\textbf{bold} and \\emph{em} word'))
    end)

    it('styles an argument over several lines', function()
      T.eq({ 'x *one*', '*two* y' }, shown({ 'x \\textbf{one', 'two} y' }))
    end)

    it('shows citations in brackets but leaves one with a page alone', function()
      T.eq('see [knuth,lamport]', shown('see \\cite{knuth,lamport}'))
      T.eq('see \\cite[p.~5]{knuth}', shown('see \\cite[p.~5]{knuth}'))
    end)

    it('turns \\item into a bullet', function()
      T.eq(
        { '\\begin{itemize}', '  • one', '\\end{itemize}' },
        shown({ '\\begin{itemize}', '  \\item one', '\\end{itemize}' })
      )
    end)

    it('shows spacing commands as a space', function()
      -- The source space after `\\quad` is still there.
      T.eq('$a b$ x  y', shown('$a\\,b$ x\\quad y'))
    end)
  end)

  it('switches categories off one by one', function()
    T.eq('$\\alpha ≤$', shown('$\\alpha \\leq$', { greek = false }))
    config.setup({})
    T.eq('$α \\leq$', shown('$\\alpha \\leq$', { math_symbols = false }))
  end)

  it('takes custom commands', function()
    T.eq(
      '$x ∈ ℝ$, see ☞',
      shown('$x \\in \\R$, see \\hand', { custom = { ['\\R'] = 'ℝ', ['\\hand'] = '☞' } })
    )
  end)

  it('draws through the decoration provider', function()
    local bufnr = H.buf({ '$\\alpha$' })
    conceal.attach(bufnr)
    vim.wo.conceallevel = 2
    -- A redraw runs the provider; it must neither fail nor leave marks
    -- behind, since they are ephemeral.
    vim.cmd('redraw')
    T.eq({}, vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, {}))
    vim.wo.conceallevel = 0
  end)
end)
