local H = require('tests.helpers')
local textobj = require('nvim-tex.textobj')

--- The text the object `fn` selects, with the cursor first placed on the
--- first occurrence of `needle`.
---@param lines string[]
---@param needle string
---@param fn function
---@return string|nil
local function selected(lines, needle, fn)
  H.buf(lines)
  H.cursor_at(needle)
  local selection = H.selection(fn)
  return selection and H.selected_text(selection) or nil
end

describe('textobj', function()
  before_each(H.need_parser)
  after_each(H.cleanup)

  describe('environment', function()
    local ENV = {
      '\\begin{itemize}',
      '  \\item one',
      '  \\item two',
      '\\end{itemize}',
    }

    it('ae takes the \\begin and \\end with it', function()
      T.eq(
        table.concat(ENV, '\n'),
        selected(ENV, 'one', function()
          textobj.environment(false)
        end)
      )
    end)

    it('ie leaves the markers behind', function()
      T.eq(
        '  \\item one\n  \\item two',
        selected(ENV, 'one', function()
          textobj.environment(true)
        end)
      )
    end)

    it('selects the body linewise when it has lines of its own', function()
      H.buf(ENV)
      H.cursor_at('one')
      local selection = H.selection(function()
        textobj.environment(true)
      end)
      T.eq('V', selection.mode)
    end)

    it('skips the outer document environment', function()
      local lines = {
        '\\begin{document}',
        '\\begin{center}',
        'middle',
        '\\end{center}',
        '\\end{document}',
      }
      T.eq(
        '\\begin{center}\nmiddle\n\\end{center}',
        selected(lines, 'middle', function()
          textobj.environment(false)
        end)
      )
    end)

    it('takes the innermost of nested environments', function()
      local lines = {
        '\\begin{figure}',
        '\\begin{center}',
        'middle',
        '\\end{center}',
        '\\end{figure}',
      }
      T.eq(
        '\\begin{center}\nmiddle\n\\end{center}',
        selected(lines, 'middle', function()
          textobj.environment(false)
        end)
      )
    end)

    it('does nothing outside an environment', function()
      T.eq(
        nil,
        selected({ 'just prose' }, 'prose', function()
          textobj.environment(false)
        end)
      )
    end)
  end)

  describe('command', function()
    it('ac takes the whole command', function()
      T.eq(
        '\\textbf{bold}',
        selected({ 'a \\textbf{bold} b' }, 'bold', function()
          textobj.command(false)
        end)
      )
    end)

    it('ic takes the command name, as vimtex does', function()
      -- `dic` on `\\comm|and{arg}` is meant to leave `\\{arg}` behind.
      T.eq(
        'textbf',
        selected({ 'a \\textbf{bold} b' }, 'bold', function()
          textobj.command(true)
        end)
      )
    end)
  end)

  describe('math', function()
    it('a$ includes the dollars', function()
      T.eq(
        '$a + b$',
        selected({ 'text $a + b$ text' }, 'a + b', function()
          textobj.math(false)
        end)
      )
    end)

    it('i$ excludes them', function()
      T.eq(
        'a + b',
        selected({ 'text $a + b$ text' }, 'a + b', function()
          textobj.math(true)
        end)
      )
    end)

    it('works for \\( ... \\)', function()
      T.eq(
        '\\(a + b\\)',
        selected({ 'text \\(a + b\\) text' }, 'a + b', function()
          textobj.math(false)
        end)
      )
    end)

    it('takes the body of a display math block linewise', function()
      H.buf({ '\\[', 'x = y', '\\]' })
      H.cursor_at('x = y')
      local selection = H.selection(function()
        textobj.math(true)
      end)
      T.eq('V', selection.mode)
      T.eq('x = y', H.selected_text(selection))
    end)

    it('keeps the delimiters of a display math block for a$', function()
      T.eq(
        '\\[\nx = y\n\\]',
        selected({ '\\[', 'x = y', '\\]' }, 'x = y', function()
          textobj.math(false)
        end)
      )
    end)
  end)

  describe('delimiter', function()
    it('ad takes the braces with it', function()
      T.eq(
        '{inner}',
        selected({ '\\textbf{inner}' }, 'inner', function()
          textobj.delimiter(false)
        end)
      )
    end)

    it('id leaves them out', function()
      T.eq(
        'inner',
        selected({ '\\textbf{inner}' }, 'inner', function()
          textobj.delimiter(true)
        end)
      )
    end)

    it('understands \\left( ... \\right)', function()
      -- Everything between the delimiters, surrounding spaces included.
      T.eq(
        ' x + y ',
        selected({ '$\\left( x + y \\right)$' }, 'x + y', function()
          textobj.delimiter(true)
        end)
      )
    end)
  end)

  describe('item', function()
    it('am takes the \\item and its text', function()
      local lines = {
        '\\begin{itemize}',
        '  \\item one',
        '  \\item two',
        '\\end{itemize}',
      }
      T.matches(
        'one',
        selected(lines, 'one', function()
          textobj.item(false)
        end)
      )
    end)
  end)

  describe('section', function()
    it('aP covers the section and its body', function()
      local lines = {
        '\\section{One}',
        'first body',
        '\\section{Two}',
        'second body',
      }
      local text = selected(lines, 'first body', function()
        textobj.section(false)
      end)
      T.matches('\\section{One}', text)
      T.matches('first body', text)
      T.falsy(text:find('second body'))
    end)
  end)
end)
