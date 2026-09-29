local H = require('tests.helpers')
local config = require('nvim-tex.config')
local snacks = require('nvim-tex.viewer.snacks')
local viewer = require('nvim-tex.viewer')

describe('viewer snacks', function()
  local is_running, view = viewer.is_running, viewer.view
  local placed, viewed

  --- A compiled fragment and a stand-in for snacks.nvim.
  ---@param supported boolean the terminal can show images
  ---@param placeholders boolean|nil it has unicode placeholders
  local function setup(supported, placeholders)
    local dir = H.tmpdir()
    H.write(dir .. '/tikz-preview.pdf', '%PDF')
    placed, viewed = nil, nil
    package.loaded.snacks = {
      image = {
        config = { enabled = true, doc = { max_width = 30, max_height = 10 } },
        supports_terminal = function()
          return supported
        end,
        terminal = {
          env = function()
            return { placeholders = placeholders }
          end,
        },
        placement = {
          new = function(buf, src, opts)
            placed = {
              buf = buf,
              src = src,
              opts = opts,
              img = { info = { dpi = { width = 192, height = 192 } } },
              close = function() end,
            }
            placed.state = function()
              return { loc = { 1, 0, width = 12, height = 5 } }
            end
            return placed
          end,
        },
      },
    }
    viewer.is_running = function()
      return false
    end
    viewer.view = function(fragment)
      viewed = fragment
    end
    return H.project(dir .. '/tikz-preview.tex')
  end

  after_each(function()
    snacks.close()
    package.loaded.snacks = nil
    viewer.is_running, viewer.view = is_running, view
    vim.cmd('silent! %bwipeout!')
    H.cleanup()
  end)

  it('shows a fragment in virtual lines below the anchor', function()
    local fragment = setup(true, true)
    local buf = H.buf({ '\\begin{tikzpicture}', '\\end{tikzpicture}', 'after' })
    viewer.show_fragment(fragment, snacks.anchor(buf, 1))
    T.eq(nil, viewed)
    T.ok(placed)
    T.eq(buf, placed.buf)
    T.eq(true, placed.opts.inline)
    T.matches('/tikz%-preview%-%d+%.pdf$', placed.src)
    T.eq(1, vim.fn.filereadable(placed.src))
    T.eq(30, placed.opts.max_width)

    -- The anchor follows edits above it, and the image is magnified.
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 'new' })
    local wins = #vim.api.nvim_list_wins()
    placed.opts.on_update_pre(placed)
    placed.opts.on_update_pre(placed)
    T.eq(wins, #vim.api.nvim_list_wins())
    T.eq({ 3, 0 }, placed.opts.pos)
    T.eq({ 3, 0, 3, #'\\end{tikzpicture}' }, placed.opts.range)
    T.eq(96, placed.img.info.dpi.width)

    -- It stays when the cursor moves.
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', {})
    T.eq(1, vim.fn.filereadable(placed.src))

    snacks.close()
    T.eq(0, vim.fn.filereadable(placed.src))
    T.eq({}, vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, {}))
  end)

  it('shows a fragment in a float below the anchor without placeholders', function()
    local fragment = setup(true, false)
    local buf = H.buf({ 'a', 'b', 'c' })
    viewer.show_fragment(fragment, snacks.anchor(buf, 1))
    T.ok(placed)
    T.ok(placed.buf ~= buf)

    local before = #vim.api.nvim_list_wins()
    placed.opts.on_update_pre(placed)
    local wins = vim.api.nvim_list_wins()
    T.eq(before + 1, #wins)
    local win = wins[#wins]
    T.eq(placed.buf, vim.api.nvim_win_get_buf(win))
    T.eq(12, vim.api.nvim_win_get_width(win))
    T.eq(5, vim.api.nvim_win_get_height(win))
    T.eq({ 1, 0 }, vim.api.nvim_win_get_config(win).bufpos)

    vim.cmd('TexPreviewClose')
    T.eq(false, vim.api.nvim_win_is_valid(win))
    T.eq(0, vim.fn.filereadable(placed.src))
  end)

  it('falls back to the viewer', function()
    local fragment = setup(false)
    viewer.show_fragment(fragment)
    T.eq(nil, placed)
    T.eq(fragment, viewed)

    fragment = setup(true)
    config.setup({ view = { snacks = { enabled = false } } })
    viewer.show_fragment(fragment)
    T.eq(nil, placed)
    T.eq(fragment, viewed)
  end)
end)
