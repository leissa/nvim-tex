local H = require('tests.helpers')
local motions = require('nvim-tex.motions')

local DOC = {
  '\\documentclass{article}', -- 1
  '\\begin{document}', -- 2
  '\\section{One}', -- 3
  'Some prose with $a + b$ in it.', -- 4
  '\\begin{itemize}', -- 5
  '  \\item first', -- 6
  '\\end{itemize}', -- 7
  '% a comment', -- 8
  '\\section{Two}', -- 9
  '\\[', -- 10
  '  x = y', -- 11
  '\\]', -- 12
  '\\end{document}', -- 13
}

--- The cursor row after running `fn` from `(row, col)`.
---@param row integer
---@param col integer
---@param fn function
---@return integer
local function jump_from(row, col, fn)
  H.cursor(row, col)
  fn()
  return vim.api.nvim_win_get_cursor(0)[1]
end

describe('motions', function()
  before_each(function()
    H.need_parser()
    H.buf(DOC)
  end)

  after_each(H.cleanup)

  describe('sections', function()
    it(']] goes to the next section', function()
      T.eq(9, jump_from(3, 0, motions.map[']]']))
    end)

    it('[[ goes to the previous section', function()
      T.eq(3, jump_from(9, 0, motions.map['[[']))
    end)

    it('stays put when there is no next section', function()
      T.eq(9, jump_from(9, 0, motions.map[']]']))
    end)

    it('honours a count', function()
      -- Driven through the real mapping, because `v:count1` is only set for
      -- a keypress.
      H.cursor(1, 0)
      vim.api.nvim_feedkeys('2]]', 'x', false)
      T.eq(9, vim.api.nvim_win_get_cursor(0)[1])
    end)
  end)

  describe('environments', function()
    it(']m goes to the next \\begin', function()
      T.eq(5, jump_from(3, 0, motions.map[']m']))
    end)

    it('[m goes back to the enclosing \\begin', function()
      T.eq(5, jump_from(6, 4, motions.map['[m']))
    end)

    it(']M goes to the next \\end', function()
      T.eq(7, jump_from(6, 0, motions.map[']M']))
    end)

    it('[M goes to the previous \\end', function()
      T.eq(7, jump_from(9, 0, motions.map['[M']))
    end)
  end)

  describe('math', function()
    it(']n goes to the next math zone', function()
      T.eq(10, jump_from(5, 0, motions.map[']n']))
    end)

    it('[n goes back to the previous math zone', function()
      T.eq(4, jump_from(9, 0, motions.map['[n']))
    end)

    it(']N goes to the end of the next math zone', function()
      T.eq(12, jump_from(5, 0, motions.map[']N']))
    end)
  end)

  describe('comments', function()
    it(']/ finds the next comment', function()
      T.eq(8, jump_from(3, 0, motions.map[']/']))
    end)

    it('[/ finds the previous one', function()
      T.eq(8, jump_from(11, 0, motions.map['[/']))
    end)
  end)

  describe('frames', function()
    it(']r only stops at a frame environment', function()
      H.buf({
        '\\begin{itemize}',
        '\\item a',
        '\\end{itemize}',
        '\\begin{frame}',
        'slide',
        '\\end{frame}',
      })
      T.eq(4, jump_from(1, 0, motions.map[']r']))
    end)
  end)

  describe('%', function()
    it('jumps from \\begin to the matching \\end', function()
      T.eq(7, jump_from(5, 2, motions.map['%']))
    end)

    it('jumps back from \\end to \\begin', function()
      T.eq(5, jump_from(7, 2, motions.map['%']))
    end)

    it('matches the delimiters of a display math zone', function()
      T.eq(12, jump_from(10, 0, motions.map['%']))
      T.eq(10, jump_from(12, 1, motions.map['%']))
    end)

    it('falls back to the built-in % inside a group', function()
      H.buf({ '\\textbf{bold}' })
      H.cursor(1, 7) -- on the opening brace
      motions.map['%']()
      T.eq(12, vim.api.nvim_win_get_cursor(0)[2]) -- the closing brace
    end)
  end)

  describe('tikz statements', function()
    local PIC = {
      '\\begin{tikzpicture}', -- 1
      '  \\draw (a)', -- 2
      '    -- (b);', -- 3
      '  \\foreach \\i in {1,2} {', -- 4
      '    \\fill (\\i,0);', -- 5
      '  }', -- 6
      '\\end{tikzpicture}', -- 7
    }

    before_each(function()
      H.buf(PIC)
    end)

    it(']; goes to the next statement, nested ones included', function()
      T.eq(2, jump_from(1, 0, motions.map['];']))
      T.eq(4, jump_from(3, 0, motions.map['];']))
      T.eq(5, jump_from(4, 2, motions.map['];']))
    end)

    it('[; goes to the previous statement', function()
      T.eq(4, jump_from(5, 4, motions.map['[;']))
      T.eq(2, jump_from(3, 4, motions.map['[;']))
    end)
  end)
end)
