local H = require('tests.helpers')
local config = require('nvim-tex.config')
local float = require('nvim-tex.viewer.float')
local viewer = require('nvim-tex.viewer')

describe('viewer float', function()
  local is_running, view = viewer.is_running, viewer.view
  local placed, viewed

  --- A compiled fragment and a stand-in for snacks.nvim.
  ---@param supported boolean the terminal can show images
  local function setup(supported)
    local dir = H.tmpdir()
    H.write(dir .. '/tikz-preview.pdf', '%PDF')
    placed, viewed = nil, nil
    package.loaded.snacks = {
      image = {
        config = { enabled = true, doc = { max_width = 30, max_height = 10 } },
        supports_terminal = function()
          return supported
        end,
        placement = {
          new = function(buf, src, opts)
            placed = { buf = buf, src = src, opts = opts, close = function() end }
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
    float.close()
    package.loaded.snacks = nil
    viewer.is_running, viewer.view = is_running, view
    vim.cmd('silent! %bwipeout!')
    H.cleanup()
  end)

  it('shows a fragment in a float at the cursor with snacks', function()
    local fragment = setup(true)
    H.buf({ 'x' })
    viewer.show_fragment(fragment)
    T.eq(nil, viewed)
    T.ok(placed)
    T.matches('/tikz%-preview%-%d+%.pdf$', placed.src)
    T.eq(1, vim.fn.filereadable(placed.src))
    T.eq(30, placed.opts.max_width)

    local before = #vim.api.nvim_list_wins()
    placed.opts.on_update_pre(placed)
    local wins = vim.api.nvim_list_wins()
    T.eq(before + 1, #wins)
    local win = wins[#wins]
    T.eq(placed.buf, vim.api.nvim_win_get_buf(win))
    T.eq(12, vim.api.nvim_win_get_width(win))
    T.eq(5, vim.api.nvim_win_get_height(win))

    float.close()
    T.eq(false, vim.api.nvim_win_is_valid(win))
    T.eq(0, vim.fn.filereadable(placed.src))
  end)

  it('falls back to the viewer', function()
    local fragment = setup(false)
    viewer.show_fragment(fragment)
    T.eq(nil, placed)
    T.eq(fragment, viewed)

    fragment = setup(true)
    config.setup({ view = { snacks = false } })
    viewer.show_fragment(fragment)
    T.eq(nil, placed)
    T.eq(fragment, viewed)
  end)
end)
