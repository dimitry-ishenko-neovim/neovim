local t = require('test.testutil')
local n = require('test.functional.testnvim')()
local Screen = require('test.functional.ui.screen')

local clear, feed = n.clear, n.feed
local source = n.source
local command = n.command
local assert_alive = n.assert_alive
local poke_eventloop = n.poke_eventloop
local exec = n.exec
local eval = n.eval
local eq = t.eq
local is_os = t.is_os
local api = n.api

local function test_cmdline(linegrid)
  local screen

  before_each(function()
    clear()
    screen = Screen.new(25, 5, { rgb = true, ext_cmdline = true, ext_linegrid = linegrid })
  end)

  it('works', function()
    feed(':')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = { {
        firstc = ':',
        content = { { '' } },
        pos = 0,
      } },
    }

    feed('sign')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign' } },
          pos = 4,
        },
      },
    }

    feed('<Left>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign' } },
          pos = 3,
        },
      },
    }

    feed('<bs>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sin' } },
          pos = 2,
        },
      },
    }

    feed('<Esc>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = { { abort = true } },
    }
  end)

  it('works with input()', function()
    feed(':call input("input", "default")<cr>')
    screen:expect({
      grid = [[
        ^                         |
        {1:~                        }|*3
                                 |
      ]],
      cmdline = {
        {
          content = { { 'default' } },
          hl_id = 0,
          pos = 7,
          prompt = 'input',
        },
      },
    })

    feed('<cr>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = { { abort = false } },
    }
  end)

  it('works with special chars and nested cmdline', function()
    feed(':xx<c-r>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'xx' } },
          pos = 2,
          special = { '"', true },
        },
      },
    }

    feed('=')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'xx' } },
          pos = 2,
          special = { '"', true },
        },
        {
          firstc = '=',
          content = { { '' } },
          pos = 0,
        },
      },
    }

    feed('1+2')
    local expectation = {
      {
        firstc = ':',
        content = { { 'xx' } },
        pos = 2,
        special = { '"', true },
      },
      {
        firstc = '=',
        content = { { '1', 26 }, { '+', 15 }, { '2', 26 } },
        pos = 3,
      },
    }

    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = expectation,
    }

    -- erase information, so we check if it is retransmitted
    command('mode')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = expectation,
      reset = true,
    }

    feed('<cr>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'xx3' } },
          pos = 3,
        },
        { abort = false },
      },
    }

    feed('<esc>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = { { abort = true } },
    }
  end)

  it('works with function definitions', function()
    feed(':function Foo()<cr>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          indent = 2,
          firstc = ':',
          content = { { '' } },
          pos = 0,
        },
      },
      cmdline_block = {
        { { 'function Foo()' } },
      },
    }

    feed('line1<cr>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          indent = 2,
          firstc = ':',
          content = { { '' } },
          pos = 0,
        },
      },
      cmdline_block = {
        { { 'function Foo()' } },
        { { '  line1' } },
      },
    }

    command('mode')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          indent = 2,
          firstc = ':',
          content = { { '' } },
          pos = 0,
        },
      },
      cmdline_block = {
        { { 'function Foo()' } },
        { { '  line1' } },
      },
      reset = true,
    }

    feed('endfunction<cr>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = { { abort = false } },
    }

    -- Try once more, to check buffer is reinitialized. #8007
    feed(':function Bar()<cr>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          indent = 2,
          firstc = ':',
          content = { { '' } },
          pos = 0,
        },
      },
      cmdline_block = {
        { { 'function Bar()' } },
      },
    }

    feed('endfunction<cr>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = { { abort = false } },
    }
  end)

  it('works with cmdline window', function()
    feed(':make')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'make' } },
          pos = 4,
        },
      },
    }

    feed('<c-f>')
    screen:expect {
      grid = [[
                               |
      {2:[No Name]                }|
      {1::}make^                    |
      {3:[Command Line]           }|
                               |
    ]],
      cmdline = { { abort = false } },
    }

    -- nested cmdline
    feed(':yank')
    screen:expect {
      grid = [[
                               |
      {2:[No Name]                }|
      {1::}make^                    |
      {3:[Command Line]           }|
                               |
    ]],
      cmdline = {
        nil,
        {
          firstc = ':',
          content = { { 'yank' } },
          pos = 4,
        },
      },
    }

    command('mode')
    screen:expect {
      grid = [[
                               |
      {2:[No Name]                }|
      {1::}make^                    |
      {3:[Command Line]           }|
                               |
    ]],
      cmdline = {
        nil,
        {
          firstc = ':',
          content = { { 'yank' } },
          pos = 4,
        },
      },
      reset = true,
    }

    feed('<c-c>')
    screen:expect {
      grid = [[
                               |
      {2:[No Name]                }|
      {1::}make^                    |
      {3:[Command Line]           }|
                               |
    ]],
      cmdline = { [2] = { abort = true } },
    }

    feed('<c-c>')
    screen:expect {
      grid = [[
      ^                         |
      {2:[No Name]                }|
      {1::}make                    |
      {3:[Command Line]           }|
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'make' } },
          pos = 4,
        },
      },
    }

    command('redraw!')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'make' } },
          pos = 4,
        },
      },
    }
  end)

  it('works with inputsecret()', function()
    feed(":call inputsecret('secret:')<cr>abc123")
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          prompt = 'secret:',
          hl_id = 0,
          content = { { '******' } },
          pos = 6,
        },
      },
    }
  end)

  it('works with highlighted cmdline', function()
    source([[
      highlight RBP1 guibg=Red
      highlight RBP2 guibg=Yellow
      highlight RBP3 guibg=Green
      highlight RBP4 guibg=Blue
      let g:NUM_LVLS = 4
      function RainBowParens(cmdline)
        let ret = []
        let i = 0
        let lvl = 0
        while i < len(a:cmdline)
          if a:cmdline[i] is# '('
            call add(ret, [i, i + 1, 'RBP' . ((lvl % g:NUM_LVLS) + 1)])
            let lvl += 1
          elseif a:cmdline[i] is# ')'
            let lvl -= 1
            call add(ret, [i, i + 1, 'RBP' . ((lvl % g:NUM_LVLS) + 1)])
          endif
          let i += 1
        endwhile
        return ret
      endfunction
      map <f5>  :let x = input({'prompt':'>','highlight':'RainBowParens'})<cr>
      "map <f5>  :let x = input({'prompt':'>'})<cr>
    ]])
    feed('<f5>(a(b)a)')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          prompt = '>',
          hl_id = 0,
          content = {
            { '(', 30 },
            { 'a' },
            { '(', 10 },
            { 'b' },
            { ')', 10 },
            { 'a' },
            { ')', 30 },
          },
          pos = 7,
        },
      },
    }
  end)

  it('works together with ext_wildmenu', function()
    local expected = {
      'define',
      'jump',
      'list',
      'place',
      'undefine',
      'unplace',
    }

    command('set wildmode=full')
    command('set wildmenu')
    screen:set_option('ext_wildmenu', true)
    feed(':sign <tab>')

    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign define' } },
          pos = 11,
        },
      },
      wildmenu_items = expected,
      wildmenu_pos = 0,
    }

    feed('<tab>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign jump' } },
          pos = 9,
        },
      },
      wildmenu_items = expected,
      wildmenu_pos = 1,
    }

    feed('<left><left>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign ' } },
          pos = 5,
        },
      },
      wildmenu_items = expected,
      wildmenu_pos = -1,
    }

    feed('<right>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign define' } },
          pos = 11,
        },
      },
      wildmenu_items = expected,
      wildmenu_pos = 0,
    }

    feed('a')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign definea' } },
          pos = 12,
        },
      },
    }
  end)

  it('works together with ext_popupmenu', function()
    local expected = {
      { 'define', '', '', '' },
      { 'jump', '', '', '' },
      { 'list', '', '', '' },
      { 'place', '', '', '' },
      { 'undefine', '', '', '' },
      { 'unplace', '', '', '' },
    }

    command('set wildmode=full')
    command('set wildmenu')
    screen:set_option('ext_popupmenu', true)
    feed(':sign <tab>')

    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign define' } },
          pos = 11,
        },
      },
      popupmenu = { items = expected, pos = 0, anchor = { -1, 0, 5 } },
    }

    feed('<tab>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign jump' } },
          pos = 9,
        },
      },
      popupmenu = { items = expected, pos = 1, anchor = { -1, 0, 5 } },
    }

    feed('<left><left>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign ' } },
          pos = 5,
        },
      },
      popupmenu = { items = expected, pos = -1, anchor = { -1, 0, 5 } },
    }

    feed('<right>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign define' } },
          pos = 11,
        },
      },
      popupmenu = { items = expected, pos = 0, anchor = { -1, 0, 5 } },
    }

    feed('a')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign definea' } },
          pos = 12,
        },
      },
    }
    feed('<esc>')

    -- check positioning with multibyte char in pattern
    command('e långfile1')
    command('sp långfile2')
    feed(':b lå<tab>')
    screen:expect {
      grid = [[
      ^                         |
      {3:långfile2                }|
                               |
      {2:långfile1                }|
                               |
    ]],
      popupmenu = {
        anchor = { -1, 0, 2 },
        items = { { 'långfile1', '', '', '' }, { 'långfile2', '', '', '' } },
        pos = 0,
      },
      cmdline = {
        {
          content = { { 'b långfile1' } },
          firstc = ':',
          pos = 12,
        },
      },
    }
  end)

  it('ext_wildmenu takes precedence over ext_popupmenu', function()
    local expected = {
      'define',
      'jump',
      'list',
      'place',
      'undefine',
      'unplace',
    }

    command('set wildmode=full')
    command('set wildmenu')
    screen:set_option('ext_wildmenu', true)
    screen:set_option('ext_popupmenu', true)
    feed(':sign <tab>')

    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          firstc = ':',
          content = { { 'sign define' } },
          pos = 11,
        },
      },
      wildmenu_items = expected,
      wildmenu_pos = 0,
    }
  end)

  it("doesn't send invalid events when aborting mapping #10000", function()
    command('set notimeout')
    command('cnoremap ab c')

    feed(':xa')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
      cmdline = {
        {
          content = { { 'x' } },
          firstc = ':',
          pos = 1,
          special = { 'a', false },
        },
      },
    }

    -- This used to send an invalid event where pos where larger than the total
    -- length of content. Checked in _handle_cmdline_show.
    feed('<esc>')
    screen:expect({
      grid = [[
        ^                         |
        {1:~                        }|*3
                                 |
      ]],
      cmdline = { { abort = true } },
    })
  end)

  it('does not move cursor to curwin #20309', function()
    local win = api.nvim_get_current_win()
    command('norm icmdlinewin')
    command('new')
    command('norm icurwin')
    feed(':')
    api.nvim_win_set_cursor(win, { 1, 7 })
    api.nvim__redraw({ win = win, cursor = true })
    screen:expect {
      grid = [[
      curwin                   |
      {3:[No Name] [+]            }|
      cmdline^win               |
      {2:[No Name] [+]            }|
                               |
    ]],
      cmdline = { {
        content = { { '' } },
        firstc = ':',
        pos = 0,
      } },
    }
  end)

  it('show prompt hl_id', function()
    screen:expect([[
      ^                         |
      {1:~                        }|*3
                               |
    ]])
    feed(':echohl Error | call input("Prompt:")<CR>')
    screen:expect({
      grid = [[
        ^                         |
        {1:~                        }|*3
                                 |
      ]],
      cmdline = {
        {
          content = { { '' } },
          hl_id = 242,
          pos = 0,
          prompt = 'Prompt:',
        },
      },
    })
  end)

  it('works with conditionals', function()
    local s1 = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]]
    screen:expect(s1)
    feed(':if 1<CR>')
    screen:expect({
      grid = s1,
      cmdline = {
        {
          content = { { '' } },
          firstc = ':',
          indent = 2,
          pos = 0,
        },
      },
      cmdline_block = { { { 'if 1' } } },
    })
    feed('let x = 1<CR>')
    screen:expect({
      grid = s1,
      cmdline = {
        {
          content = { { '' } },
          firstc = ':',
          indent = 2,
          pos = 0,
        },
      },
      cmdline_block = { { { 'if 1' } }, { { '  let x = 1' } } },
    })
    feed('<CR>')
    eq('let x = 1', eval('@:'))
    screen:expect({
      grid = s1,
      cmdline = {
        {
          content = { { '' } },
          firstc = ':',
          indent = 2,
          pos = 0,
        },
      },
      cmdline_block = { { { 'if 1' } }, { { '  let x = 1' } }, { { '  ' } } },
    })
    feed('endif')
    screen:expect({
      grid = s1,
      cmdline = {
        {
          content = { { 'endif' } },
          firstc = ':',
          indent = 2,
          pos = 5,
        },
      },
      cmdline_block = { { { 'if 1' } }, { { '  let x = 1' } }, { { '  ' } } },
    })
    feed('<CR>')
    screen:expect({
      grid = s1,
      cmdline = { { abort = false } },
    })
  end)
end

-- the representation of cmdline and cmdline_block contents changed with ext_linegrid
-- (which uses indexed highlights) so make sure to test both
describe('ui/ext_cmdline', function()
  test_cmdline(true)
end)
describe('ui/ext_cmdline (legacy highlights)', function()
  test_cmdline(false)
end)

describe('cmdline redraw', function()
  local screen
  before_each(function()
    clear()
    screen = Screen.new(25, 5, { rgb = true })
  end)

  it('with timer', function()
    feed(':012345678901234567890123456789')
    screen:expect {
      grid = [[
                             |
    {1:~                        }|
    {3:                         }|
    :012345678901234567890123|
    456789^                   |
    ]],
    }
    command('call timer_start(0, {-> 1})')
    screen:expect {
      grid = [[
                             |
    {1:~                        }|
    {3:                         }|
    :012345678901234567890123|
    456789^                   |
    ]],
      unchanged = true,
      timeout = 100,
    }
  end)

  it('with <Cmd>', function()
    if is_os('bsd') then
      pending('FIXME #10804')
    end
    command('cmap a <Cmd>call sin(0)<CR>') -- no-op
    feed(':012345678901234567890123456789')
    screen:expect {
      grid = [[
                             |
    {1:~                        }|
    {3:                         }|
    :012345678901234567890123|
    456789^                   |
    ]],
    }
    feed('a')
    screen:expect {
      grid = [[
                             |
    {1:~                        }|
    {3:                         }|
    :012345678901234567890123|
    456789^                   |
    ]],
      unchanged = true,
    }
  end)

  it('after pressing Ctrl-C in cmdwin in Visual mode #18967', function()
    screen:try_resize(40, 10)
    command('set cmdwinheight=3')
    feed('q:iabc<Esc>vhh')
    screen:expect([[
                                              |
      {1:~                                       }|*3
      {2:[No Name]                               }|
      {1::}^a{17:bc}                                    |
      {1:~                                       }|*2
      {3:[Command Line]                          }|
      {5:-- VISUAL --}                            |
    ]])
    feed('<C-C>')
    screen:expect([[
                                              |
      {1:~                                       }|*3
      {2:[No Name]                               }|
      {1::}a{17:bc}                                    |
      {1:~                                       }|*2
      {3:[Command Line]                          }|
      :^abc                                    |
    ]])
  end)

  it('with rightleftcmd', function()
    command('set rightleft rightleftcmd=search shortmess+=s')
    api.nvim_buf_set_lines(0, 0, -1, true, { "let's rock!" })
    screen:expect {
      grid = [[
                    !kcor s'te^l|
      {1:                        ~}|*3
                               |
    ]],
    }

    feed '/'
    screen:expect {
      grid = [[
                    !kcor s'tel|
      {1:                        ~}|*3
                             ^ /|
    ]],
    }

    feed "let's"
    -- note: cursor looks off but looks alright in real use
    -- when rendered as a block so it touches the end of the text
    screen:expect {
      grid = [[
                    !kcor {2:s'tel}|
      {1:                        ~}|*3
                        ^ s'tel/|
    ]],
    }

    -- cursor movement
    feed '<space>'
    screen:expect {
      grid = [[
                    !kcor{2: s'tel}|
      {1:                        ~}|*3
                       ^  s'tel/|
    ]],
    }

    feed 'rock'
    screen:expect {
      grid = [[
                    !{2:kcor s'tel}|
      {1:                        ~}|*3
                   ^ kcor s'tel/|
    ]],
    }

    feed '<right>'
    screen:expect {
      grid = [[
                    !{2:kcor s'tel}|
      {1:                        ~}|*3
                    ^kcor s'tel/|
    ]],
    }

    feed '<left>'
    screen:expect {
      grid = [[
                    !{2:kcor s'tel}|
      {1:                        ~}|*3
                   ^ kcor s'tel/|
    ]],
    }

    feed '<cr>'
    screen:expect {
      grid = [[
                    !{10:kcor s'te^l}|
      {1:                        ~}|*3
      kcor s'tel/              |
    ]],
    }
  end)

  it('prompt with silent mapping and screen update', function()
    command([[nmap <silent> T :call confirm("Save changes?", "&Yes\n&No\n&Cancel")<CR>]])
    feed('T')
    screen:expect([[
                               |
      {3:                         }|
                               |
      {6:Save changes?}            |
      {6:[Y]es, (N)o, (C)ancel: }^  |
    ]])
    command('call setline(1, "foo") | redraw')
    screen:expect([[
      foo                      |
      {3:                         }|
                               |
      {6:Save changes?}            |
      {6:[Y]es, (N)o, (C)ancel: }^  |
    ]])
    feed('Y')
    screen:expect([[
      ^foo                      |
      {1:~                        }|*3
                               |
    ]])
    screen:try_resize(75, screen._height)
    feed(':call inputlist(["foo", "bar"])<CR>')
    screen:expect([[
      foo                                                                        |
      {3:                                                                           }|
      foo                                                                        |
      bar                                                                        |
      Type number and <Enter> or click with the mouse (q or empty cancels): ^     |
    ]])
    command('redraw')
    screen:expect_unchanged()
  end)

  it('substitute confirm prompt does not scroll', function()
    screen:try_resize(75, screen._height)
    command('call setline(1, "foo")')
    command('set report=0')
    feed(':%s/foo/bar/c<CR>')
    screen:expect([[
      {2:foo}                                                                        |
      {1:~                                                                          }|*3
      {6:replace with bar? (y)es/(n)o/(a)ll/(q)uit/(l)ast/scroll up(^E)/down(^Y)}^    |
    ]])
    feed('y')
    screen:expect([[
      ^bar                                                                        |
      {1:~                                                                          }|*3
      1 substitution on 1 line                                                   |
    ]])
  end)
end)

describe('statusline is redrawn on entering cmdline', function()
  local screen

  before_each(function()
    clear()
    screen = Screen.new(25, 5)
    command('set laststatus=2')
  end)

  it('from normal mode', function()
    command('set statusline=%{mode()}')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*2
      {3:n                        }|
                               |
    ]],
    }

    feed(':')
    screen:expect {
      grid = [[
                               |
      {1:~                        }|*2
      {3:c                        }|
      :^                        |
    ]],
    }
  end)

  it('from normal mode when : is mapped', function()
    command('set statusline=%{mode()}')
    command('nnoremap ; :')

    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*2
      {3:n                        }|
                               |
    ]],
    }

    feed(';')
    screen:expect {
      grid = [[
                               |
      {1:~                        }|*2
      {3:c                        }|
      :^                        |
    ]],
    }
  end)

  it('with scrolled messages', function()
    screen:try_resize(35, 14)
    exec([[
      let g:count = 0
      autocmd CmdlineEnter * let g:count += 1
      split
      resize 1
      setlocal statusline=%{mode()}%{g:count}
      setlocal winbar=%{mode()}%{g:count}
    ]])
    feed(':echoerr doesnotexist<cr>')
    screen:expect {
      grid = [[
      {5:c1                                 }|
                                         |
      {3:c1                                 }|
                                         |
      {1:~                                  }|*5
      {3:                                   }|
      {9:E121: Undefined variable: doesnotex}|
      {9:ist}                                |
      {6:Press ENTER or type command to cont}|
      {6:inue}^                               |
    ]],
    }
    feed(':echoerr doesnotexist<cr>')
    screen:expect {
      grid = [[
      {5:c2                                 }|
                                         |
      {3:c2                                 }|
                                         |
      {1:~                                  }|*2
      {3:                                   }|
      {9:E121: Undefined variable: doesnotex}|
      {9:ist}                                |
      {6:Press ENTER or type command to cont}|
      {9:E121: Undefined variable: doesnotex}|
      {9:ist}                                |
      {6:Press ENTER or type command to cont}|
      {6:inue}^                               |
    ]],
    }

    feed(':echoerr doesnotexist<cr>')
    screen:expect {
      grid = [[
      {5:c3                                 }|
                                         |
      {3:c3                                 }|
      {3:                                   }|
      {9:E121: Undefined variable: doesnotex}|
      {9:ist}                                |
      {6:Press ENTER or type command to cont}|
      {9:E121: Undefined variable: doesnotex}|
      {9:ist}                                |
      {6:Press ENTER or type command to cont}|
      {9:E121: Undefined variable: doesnotex}|
      {9:ist}                                |
      {6:Press ENTER or type command to cont}|
      {6:inue}^                               |
    ]],
    }

    feed('<cr>')
    screen:expect {
      grid = [[
      {5:n3                                 }|
      ^                                   |
      {3:n3                                 }|
                                         |
      {1:~                                  }|*8
      {2:[No Name]                          }|
                                         |
    ]],
    }
  end)

  describe('if custom statusline is set by', function()
    before_each(function()
      command('set statusline=')
      screen:expect {
        grid = [[
        ^                         |
        {1:~                        }|*2
        {3:[No Name]                }|
                                 |
      ]],
      }
    end)

    it('CmdlineEnter autocommand', function()
      command('autocmd CmdlineEnter * set statusline=command')
      feed(':')
      screen:expect {
        grid = [[
                                 |
        {1:~                        }|*2
        {3:command                  }|
        :^                        |
      ]],
      }
    end)

    it('ModeChanged autocommand', function()
      command('autocmd ModeChanged *:c set statusline=command')
      feed(':')
      screen:expect {
        grid = [[
                                 |
        {1:~                        }|*2
        {3:command                  }|
        :^                        |
      ]],
      }
    end)
  end)
end)

it('tabline is not redrawn in Ex mode #24122', function()
  clear()
  local screen = Screen.new(60, 5)

  exec([[
    set showtabline=2
    set tabline=%!MyTabLine()

    function! MyTabLine()

      return "foo"
    endfunction
  ]])

  feed('gQ')
  screen:expect {
    grid = [[
    {2:foo                                                         }|
                                                                |
    {3:                                                            }|
    Entering Ex mode.  Type "visual" to go to Normal mode.      |
    :^                                                           |
  ]],
  }

  feed('echo 1<CR>')
  screen:expect {
    grid = [[
    {3:                                                            }|
    Entering Ex mode.  Type "visual" to go to Normal mode.      |
    :echo 1                                                     |
    1                                                           |
    :^                                                           |
  ]],
  }
end)

describe('cmdline height', function()
  before_each(clear)

  it('does not crash resized screen #14263', function()
    local screen = Screen.new(25, 10)
    command('set cmdheight=9999')
    screen:try_resize(25, 5)
    assert_alive()
  end)

  it('unchanged when restoring window sizes with global statusline', function()
    command('set cmdheight=2 laststatus=2')
    feed('q:')
    command('set cmdheight=1 laststatus=3 | quit')
    -- Available lines changed, so closing cmdwin should skip restoring window sizes, leaving the
    -- cmdheight unchanged.
    eq(1, eval('&cmdheight'))
  end)

  it('not increased to 0 from 1 with wincmd _', function()
    command('set cmdheight=0 laststatus=0')
    command('wincmd _')
    eq(0, eval('&cmdheight'))
  end)
end)

describe('cmdheight=0', function()
  local screen
  before_each(function()
    clear()
    screen = Screen.new(25, 5)
  end)

  it('with redrawdebug=invalid resize -1', function()
    command('set redrawdebug=invalid cmdheight=0 noruler laststatus=0')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*4
    ]],
    }
    feed(':resize -1<CR>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
                               |
    ]],
    }
    assert_alive()
  end)

  it('with cmdheight=1 noruler laststatus=2', function()
    command('set cmdheight=1 noruler laststatus=2')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*2
      {3:[No Name]                }|
                               |
    ]],
    }
  end)

  it('with cmdheight=0 noruler laststatus=2', function()
    command('set cmdheight=0 noruler laststatus=2')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
      {3:[No Name]                }|
    ]],
    }
  end)

  it('with cmdheight=0 ruler laststatus=0', function()
    command('set cmdheight=0 ruler laststatus=0')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*4
    ]],
    }
  end)

  it('with cmdheight=0 ruler laststatus=0', function()
    command('set cmdheight=0 noruler laststatus=0 showmode')
    feed('i')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*4
    ]],
      showmode = {},
    }
    feed('<Esc>')
    eq(0, eval('&cmdheight'))
  end)

  it('with cmdheight=0 ruler rulerformat laststatus=0', function()
    command('set cmdheight=0 noruler laststatus=0 rulerformat=%l,%c%= showmode')
    feed('i')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*4
    ]],
      showmode = {},
    }
    feed('<Esc>')
    eq(0, eval('&cmdheight'))
  end)

  it('with showmode', function()
    command('set cmdheight=1 noruler laststatus=0 showmode')
    feed('i')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
      {5:-- INSERT --}             |
    ]],
    }
    feed('<Esc>')
    eq(1, eval('&cmdheight'))
  end)

  it('when using command line', function()
    command('set cmdheight=0 noruler laststatus=0')
    feed(':')
    screen:expect {
      grid = [[
                               |
      {1:~                        }|*3
      :^                        |
    ]],
    }
    eq(0, eval('&cmdheight'))
    feed('<cr>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*4
    ]],
      showmode = {},
    }
    eq(0, eval('&cmdheight'))
  end)

  it('when using input()', function()
    command('set cmdheight=0 noruler laststatus=0')
    feed(':call input("foo >")<cr>')
    screen:expect {
      grid = [[
                               |
      {1:~                        }|
      {3:                         }|
      :call input("foo >")     |
      foo >^                    |
    ]],
    }
    eq(0, eval('&cmdheight'))
    feed('<cr>')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*4
    ]],
      showmode = {},
    }
    eq(0, eval('&cmdheight'))
  end)

  it('with winbar and splits', function()
    command('set cmdheight=0 noruler laststatus=3 winbar=foo')
    feed(':split<CR>')
    screen:expect {
      grid = [[
      {3:                         }|
      :split                   |
      {9:E36: Not enough room}     |
      {6:Press ENTER or type comma}|
      {6:nd to continue}^           |
    ]],
    }
    feed('<CR>')
    screen:expect {
      grid = [[
      {5:foo                      }|
      ^                         |
      {1:~                        }|*2
      {3:[No Name]                }|
    ]],
    }
    feed(':')
    screen:expect {
      grid = [[
      {5:foo                      }|
                               |
      {1:~                        }|*2
      :^                        |
    ]],
    }
    feed('<Esc>')
    screen:expect {
      grid = [[
      {5:foo                      }|
      ^                         |
      {1:~                        }|*2
      {3:[No Name]                }|
    ]],
      showmode = {},
    }
    eq(0, eval('&cmdheight'))

    assert_alive()
  end)

  it('when macro with lastline', function()
    command('set cmdheight=0 display=lastline')
    feed('qq')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*4
    ]],
    }
    feed('q')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*4
    ]],
      unchanged = true,
    }
  end)

  it('when substitute text', function()
    command('set cmdheight=0 noruler laststatus=3')
    feed('ifoo<ESC>')
    screen:try_resize(screen._width, 7)
    screen:expect([[
      fo^o                      |
      {1:~                        }|*5
      {3:[No Name] [+]            }|
    ]])

    feed(':%s/foo/bar/gc<CR>')
    screen:expect([[
      {2:foo}                      |
      {3:                         }|
                               |*2
      {6:replace with bar? (y)es/(}|
      {6:n)o/(a)ll/(q)uit/(l)ast/s}|
      {6:croll up(^E)/down(^Y)}^    |
    ]])

    feed('y')
    screen:expect([[
      ^bar                      |
      {1:~                        }|*5
      {3:[No Name] [+]            }|
    ]])

    assert_alive()
  end)

  it('when window resize', function()
    command('set cmdheight=0')
    feed('<C-w>+')
    eq(0, eval('&cmdheight'))
  end)

  it('with non-silent mappings with cmdline', function()
    command('set cmdheight=0')
    command('map <f3> :nohlsearch<cr>')
    feed('iaabbaa<esc>/aa<cr>')
    screen:expect {
      grid = [[
      {10:^aa}bb{10:aa}                   |
      {1:~                        }|*4
    ]],
    }

    feed('<f3>')
    screen:expect {
      grid = [[
      ^aabbaa                   |
      {1:~                        }|*4
    ]],
    }
  end)

  it('with silent! at startup', function()
    clear { args = { '-c', 'set cmdheight=0', '-c', 'autocmd VimEnter * silent! call Foo()' } }
    screen = Screen.new(25, 5)
    -- doesn't crash while not displaying silent! error message
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*4
    ]],
    }
  end)

  it('with multigrid', function()
    clear { args = { '--cmd', 'set cmdheight=0' } }
    screen = Screen.new(25, 5, { ext_multigrid = true })
    api.nvim_buf_set_lines(0, 0, -1, true, { 'p' })
    screen:expect {
      grid = [[
    ## grid 1
      [2:-------------------------]|*5
    ## grid 2
      ^p                        |
      {1:~                        }|*4
    ## grid 3
    ]],
      win_viewport = {
        [2] = {
          win = 1000,
          topline = 0,
          botline = 2,
          curline = 0,
          curcol = 0,
          linecount = 1,
          sum_scroll_delta = 0,
        },
      },
    }

    feed '/p'
    screen:expect {
      grid = [[
    ## grid 1
      [2:-------------------------]|*4
      [3:-------------------------]|
    ## grid 2
      {2:p}                        |
      {1:~                        }|*4
    ## grid 3
      /p^                       |
    ]],
      win_viewport = {
        [2] = {
          win = 1000,
          topline = 0,
          botline = 2,
          curline = 0,
          curcol = 1,
          linecount = 1,
          sum_scroll_delta = 0,
        },
      },
    }
  end)

  it('winbar is redrawn on entering cmdline and :redrawstatus #20336', function()
    exec([[
      set cmdheight=0
      set winbar=%{mode()}%=:%{getcmdline()}
    ]])
    feed(':')
    screen:expect([[
      {5:c                       :}|
                               |
      {1:~                        }|*2
      :^                        |
    ]])
    feed('echo')
    -- not redrawn yet
    screen:expect([[
      {5:c                       :}|
                               |
      {1:~                        }|*2
      :echo^                    |
    ]])
    command('redrawstatus')
    screen:expect([[
      {5:c                   :echo}|
                               |
      {1:~                        }|*2
      :echo^                    |
    ]])
  end)

  it('window equalization with laststatus=0 #20367', function()
    screen:try_resize(60, 9)
    command('set cmdheight=0 laststatus=0')
    command('vsplit')
    screen:expect([[
      ^                              │                             |
      {1:~                             }│{1:~                            }|*8
    ]])
    feed(':')
    command('split')
    feed('<Esc>')
    screen:expect([[
      ^                              │                             |
      {1:~                             }│{1:~                            }|*3
      {3:[No Name]                     }│{1:~                            }|
                                    │{1:~                            }|
      {1:~                             }│{1:~                            }|*3
    ]])
    command('resize 2')
    screen:expect([[
      ^                              │                             |
      {1:~                             }│{1:~                            }|
      {3:[No Name]                     }│{1:~                            }|
                                    │{1:~                            }|
      {1:~                             }│{1:~                            }|*5
    ]])
    feed(':')
    command('wincmd =')
    feed('<Esc>')
    screen:expect([[
      ^                              │                             |
      {1:~                             }│{1:~                            }|*3
      {3:[No Name]                     }│{1:~                            }|
                                    │{1:~                            }|
      {1:~                             }│{1:~                            }|*3
    ]])
  end)

  it('no assert failure with showcmd', function()
    command('set showcmd cmdheight=0')
    feed('d')
    screen:expect([[
      ^                         |
      {1:~                        }|*4
    ]])
    assert_alive()
  end)

  it('can only be resized to 0 if set explicitly', function()
    command('set laststatus=2')
    command('resize +1')
    screen:expect([[
      ^                         |
      {1:~                        }|*2
      {3:[No Name]                }|
                               |
    ]])
    command('set cmdheight=0')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*3
      {3:[No Name]                }|
    ]],
    }
    command('resize -1')
    screen:expect {
      grid = [[
      ^                         |
      {1:~                        }|*2
      {3:[No Name]                }|
                               |
    ]],
    }
    command('resize +1')
    screen:expect([[
      ^                         |
      {1:~                        }|*3
      {3:[No Name]                }|
    ]])
  end)

  it('can be resized with external messages', function()
    clear()
    screen = Screen.new(25, 5, { rgb = true, ext_messages = true })
    command('set laststatus=2 mouse=a')
    command('resize -1')
    screen:expect([[
      ^                         |
      {1:~                        }|*2
      {3:[No Name]                }|
                               |
    ]])
    api.nvim_input_mouse('left', 'press', '', 0, 3, 10)
    poke_eventloop()
    api.nvim_input_mouse('left', 'drag', '', 0, 4, 10)
    screen:expect([[
      ^                         |
      {1:~                        }|*3
      {3:[No Name]                }|
    ]])
  end)
end)
