local t = require('test.testutil')
local n = require('test.functional.testnvim')()
local Screen = require('test.functional.ui.screen')
local tt = require('test.functional.testterm')

local assert_alive = n.assert_alive
local feed, clear = n.feed, n.clear
local poke_eventloop = n.poke_eventloop
local nvim_prog = n.nvim_prog
local eval, feed_command, source = n.eval, n.feed_command, n.source
local pcall_err = t.pcall_err
local eq, neq = t.eq, t.neq
local api = n.api
local retry = t.retry
local testprg = n.testprg
local write_file = t.write_file
local command = n.command
local exc_exec = n.exc_exec
local matches = t.matches
local exec_lua = n.exec_lua
local sleep = vim.uv.sleep
local fn = n.fn
local is_os = t.is_os
local skip = t.skip

describe(':terminal buffer', function()
  local screen

  before_each(function()
    clear()
    command('set modifiable swapfile undolevels=20')
    screen = tt.setup_screen()
  end)

  it('terminal-mode forces various options', function()
    feed([[<C-\><C-N>]])
    command('setlocal cursorline cursorlineopt=both cursorcolumn scrolloff=4 sidescrolloff=7')
    eq(
      { 'both', 1, 1, 4, 7 },
      eval('[&l:cursorlineopt, &l:cursorline, &l:cursorcolumn, &l:scrolloff, &l:sidescrolloff]')
    )
    eq('nt', eval('mode(1)'))

    -- Enter terminal-mode ("insert" mode in :terminal).
    feed('i')
    eq('t', eval('mode(1)'))
    eq(
      { 'number', 1, 0, 0, 0 },
      eval('[&l:cursorlineopt, &l:cursorline, &l:cursorcolumn, &l:scrolloff, &l:sidescrolloff]')
    )
  end)

  it('terminal-mode does not change cursorlineopt if cursorline is disabled', function()
    feed([[<C-\><C-N>]])
    command('setlocal nocursorline cursorlineopt=both')
    feed('i')
    eq({ 0, 'both' }, eval('[&l:cursorline, &l:cursorlineopt]'))
  end)

  it('terminal-mode disables cursorline when cursorlineopt is only set to "line"', function()
    feed([[<C-\><C-N>]])
    command('setlocal cursorline cursorlineopt=line')
    feed('i')
    eq({ 0, 'line' }, eval('[&l:cursorline, &l:cursorlineopt]'))
  end)

  describe('when a new file is edited', function()
    before_each(function()
      feed('<c-\\><c-n>:set bufhidden=wipe<cr>:enew<cr>')
      screen:expect([[
        ^                                                  |
        {4:~                                                 }|*5
        :enew                                             |
      ]])
    end)

    it('will hide the buffer, ignoring the bufhidden option', function()
      feed(':bnext:l<esc>')
      screen:expect([[
        ^                                                  |
        {4:~                                                 }|*5
                                                          |
      ]])
    end)
  end)

  describe('swap and undo', function()
    before_each(function()
      feed('<c-\\><c-n>')
      screen:expect([[
        tty ready                                         |
        ^                                                  |
                                                          |*5
      ]])
    end)

    it('does not create swap files', function()
      local swapfile = api.nvim_exec('swapname', true):gsub('\n', '')
      eq(nil, io.open(swapfile))
    end)

    it('does not create undofiles files', function()
      local undofile = api.nvim_eval('undofile(bufname("%"))')
      eq(nil, io.open(undofile))
    end)
  end)

  it('cannot be modified directly', function()
    feed('<c-\\><c-n>dd')
    screen:expect([[
      tty ready                                         |
      ^                                                  |
                                                        |*4
      {8:E21: Cannot make changes, 'modifiable' is off}     |
    ]])
  end)

  it('sends data to the terminal when the "put" operator is used', function()
    feed('<c-\\><c-n>gg"ayj')
    feed_command('let @a = "appended " . @a')
    feed('"ap"ap')
    screen:expect([[
      ^tty ready                                         |
      appended tty ready                                |*2
                                                        |
                                                        |*2
      :let @a = "appended " . @a                        |
    ]])
    -- operator count is also taken into consideration
    feed('3"ap')
    screen:expect([[
      ^tty ready                                         |
      appended tty ready                                |*5
      :let @a = "appended " . @a                        |
    ]])
  end)

  it('sends data to the terminal when the ":put" command is used', function()
    feed('<c-\\><c-n>gg"ayj')
    feed_command('let @a = "appended " . @a')
    feed_command('put a')
    screen:expect([[
      ^tty ready                                         |
      appended tty ready                                |
                                                        |
                                                        |*3
      :put a                                            |
    ]])
    -- line argument is only used to move the cursor
    feed_command('6put a')
    screen:expect([[
      tty ready                                         |
      appended tty ready                                |*2
                                                        |
                                                        |
      ^                                                  |
      :6put a                                           |
    ]])
  end)

  it('can be deleted', function()
    feed('<c-\\><c-n>:bd!<cr>')
    screen:expect([[
      ^                                                  |
      {4:~                                                 }|*5
      :bd!                                              |
    ]])
    feed_command('bnext')
    screen:expect([[
      ^                                                  |
      {4:~                                                 }|*5
      :bnext                                            |
    ]])
  end)

  it('handles loss of focus gracefully', function()
    -- Change the statusline to avoid printing the file name, which varies.
    api.nvim_set_option_value('statusline', '==========', {})

    -- Save the buffer number of the terminal for later testing.
    local tbuf = eval('bufnr("%")')
    local exitcmd = is_os('win') and "['cmd', '/c', 'exit']" or "['sh', '-c', 'exit']"
    source([[
    function! SplitWindow(id, data, event)
      new
      call feedkeys("iabc\<Esc>")
    endfunction

    startinsert
    call jobstart(]] .. exitcmd .. [[, {'on_exit': function("SplitWindow")})
    call feedkeys("\<C-\>", 't')  " vim will expect <C-n>, but be exited out of
                                  " the terminal before it can be entered.
    ]])

    -- We should be in a new buffer now.
    screen:expect([[
      ab^c                                               |
      {4:~                                                 }|
      {5:==========                                        }|
      rows: 2, cols: 50                                 |
                                                        |
      {18:==========                                        }|
                                                        |
    ]])

    neq(tbuf, eval('bufnr("%")'))
    feed_command('quit!') -- Should exit the new window, not the terminal.
    eq(tbuf, eval('bufnr("%")'))
  end)

  describe('handles confirmations', function()
    it('with :confirm', function()
      feed('<c-\\><c-n>')
      feed_command('confirm bdelete')
      screen:expect { any = 'Close "term://' }
    end)

    it('with &confirm', function()
      feed('<c-\\><c-n>')
      feed_command('bdelete')
      screen:expect { any = 'E89' }
      feed('<cr>')
      eq('terminal', eval('&buftype'))
      feed_command('set confirm | bdelete')
      screen:expect { any = 'Close "term://' }
      feed('y')
      neq('terminal', eval('&buftype'))
    end)
  end)

  it('it works with set rightleft #11438', function()
    local columns = eval('&columns')
    feed(string.rep('a', columns))
    command('set rightleft')
    screen:expect([[
                                               ydaer ytt|
      ^aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|
                                                        |*4
      {3:-- TERMINAL --}                                    |
    ]])
    command('bdelete!')
  end)

  it('requires bang (!) to close a running job #15402', function()
    skip(is_os('win'), 'Test freezes the CI and makes it time out')
    eq('Vim(wqall):E948: Job still running', exc_exec('wqall'))
    for _, cmd in ipairs({ 'bdelete', '%bdelete', 'bwipeout', 'bunload' }) do
      matches(
        '^Vim%('
          .. cmd:gsub('%%', '')
          .. '%):E89: term://.*tty%-test.* will be killed %(add %! to override%)$',
        exc_exec(cmd)
      )
    end
    command('call jobstop(&channel)')
    assert(0 >= eval('jobwait([&channel], 1000)[0]'))
    command('bdelete')
  end)

  it('stops running jobs with :quit', function()
    -- Open in a new window to avoid terminating the nvim instance
    command('split')
    command('terminal')
    command('set nohidden')
    command('quit')
  end)

  it('does not segfault when pasting empty register #13955', function()
    feed('<c-\\><c-n>')
    feed_command('put a') -- register a is empty
    n.assert_alive()
  end)

  it([[can use temporary normal mode <c-\><c-o>]], function()
    eq('t', fn.mode(1))
    feed [[<c-\><c-o>]]
    screen:expect {
      grid = [[
      tty ready                                         |
      ^                                                  |
                                                        |*4
      {3:-- (terminal) --}                                  |
    ]],
    }
    eq('ntT', fn.mode(1))

    feed [[:let g:x = 17]]
    screen:expect {
      grid = [[
      tty ready                                         |
                                                        |
                                                        |*4
      :let g:x = 17^                                     |
    ]],
    }

    feed [[<cr>]]
    screen:expect {
      grid = [[
      tty ready                                         |
      ^                                                  |
                                                        |*4
      {3:-- TERMINAL --}                                    |
    ]],
    }
    eq('t', fn.mode(1))
  end)

  it('writing to an existing file with :w fails #13549', function()
    eq(
      'Vim(write):E13: File exists (add ! to override)',
      pcall_err(command, 'write test/functional/fixtures/tty-test.c')
    )
  end)

  it('external interrupt (got_int) does not hang #20726', function()
    eq({ mode = 't', blocking = false }, api.nvim_get_mode())
    command('call timer_start(0, {-> interrupt()})')
    feed('<Ignore>') -- Add input to separate two RPC requests
    eq({ mode = 't', blocking = false }, api.nvim_get_mode())
    feed([[<C-\><C-N>]])
    eq({ mode = 'nt', blocking = false }, api.nvim_get_mode())
    command('bd!')
  end)

  it('correct size when switching buffers', function()
    local term_buf = api.nvim_get_current_buf()
    command('file foo | enew | vsplit')
    api.nvim_set_current_buf(term_buf)
    screen:expect([[
      tty ready                │                        |
      ^rows: 5, cols: 25        │{4:~                       }|
                               │{4:~                       }|*3
      {17:foo                       }{1:[No Name]               }|
                                                        |
    ]])

    feed('<C-^><C-W><C-O><C-^>')
    screen:expect([[
      tty ready                                         |
      ^rows: 5, cols: 25                                 |
      rows: 6, cols: 50                                 |
                                                        |*4
    ]])
  end)
end)

describe(':terminal buffer', function()
  before_each(clear)

  it('term_close() use-after-free #4393', function()
    command('terminal yes')
    feed('<Ignore>') -- Add input to separate two RPC requests
    command('bdelete!')
  end)

  describe('TermRequest', function()
    it('emits events #26972', function()
      local term = api.nvim_open_term(0, {})
      local termbuf = api.nvim_get_current_buf()

      -- Test that <abuf> is the terminal buffer, not the current buffer
      command('au TermRequest * let g:termbuf = +expand("<abuf>")')
      command('wincmd p')

      -- cwd will be inserted in a file URI, which cannot contain backs
      local cwd = t.fix_slashes(fn.getcwd())
      local parent = cwd:match('^(.+/)')
      local expected = '\027]7;file://host' .. parent
      api.nvim_chan_send(term, string.format('%s\027\\', expected))
      eq(expected, eval('v:termrequest'))
      eq(termbuf, eval('g:termbuf'))
    end)

    it('emits events for APC', function()
      local term = api.nvim_open_term(0, {})

      -- cwd will be inserted in a file URI, which cannot contain backs
      local cwd = t.fix_slashes(fn.getcwd())
      local parent = cwd:match('^(.+/)')
      local expected = '\027_Gfile://host' .. parent
      api.nvim_chan_send(term, string.format('%s\027\\', expected))
      eq(expected, eval('v:termrequest'))
    end)

    it('synchronization #27572', function()
      command('autocmd! nvim.terminal TermRequest')
      local term = exec_lua([[
        _G.input = {}
        local term = vim.api.nvim_open_term(0, {
          on_input = function(_, _, _, data)
            table.insert(_G.input, data)
          end,
          force_crlf = false,
        })
        vim.api.nvim_create_autocmd('TermRequest', {
          callback = function(args)
            if args.data.sequence == '\027]11;?' then
              table.insert(_G.input, '\027]11;rgb:0000/0000/0000\027\\')
            end
          end
        })
        return term
      ]])
      api.nvim_chan_send(term, '\027]11;?\007\027[5n\027]11;?\007\027[5n')
      eq({
        '\027]11;rgb:0000/0000/0000\027\\',
        '\027[0n',
        '\027]11;rgb:0000/0000/0000\027\\',
        '\027[0n',
      }, exec_lua('return _G.input'))
    end)

    it('works with vim.wait() from another autocommand #32706', function()
      command('autocmd! nvim.terminal TermRequest')
      exec_lua([[
        local term = vim.api.nvim_open_term(0, {})
        vim.api.nvim_create_autocmd('TermRequest', {
          buffer = 0,
          callback = function(ev)
            _G.sequence = ev.data.sequence
            _G.v_termrequest = vim.v.termrequest
          end,
        })
        vim.api.nvim_create_autocmd('TermEnter', {
          buffer = 0,
          callback = function()
            vim.api.nvim_chan_send(term, '\027]11;?\027\\')
            _G.result = vim.wait(3000, function()
              local expected = '\027]11;?'
              return _G.sequence == expected and _G.v_termrequest == expected
            end)
          end,
        })
      ]])
      feed('i')
      retry(nil, 4000, function()
        eq(true, exec_lua('return _G.result'))
      end)
    end)

    it('includes cursor position #31609', function()
      command('autocmd! nvim.terminal TermRequest')
      local screen = Screen.new(50, 10)
      local term = exec_lua([[
        _G.cursor = {}
        local term = vim.api.nvim_open_term(0, {})
        vim.api.nvim_create_autocmd('TermRequest', {
          callback = function(args)
            _G.cursor = args.data.cursor
          end
        })
        return term
      ]])
      -- Enter terminal mode so that the cursor follows the output
      feed('a')

      -- Put some lines into the scrollback. This tests the conversion from terminal line to buffer
      -- line.
      api.nvim_chan_send(term, string.rep('>\n', 20))
      screen:expect([[
        >                                                 |*8
        ^                                                  |
        {5:-- TERMINAL --}                                    |
      ]])

      -- Emit an OSC escape sequence
      api.nvim_chan_send(term, 'Hello\nworld!\027]133;D\027\\')
      screen:expect([[
        >                                                 |*7
        Hello                                             |
        world!^                                            |
        {5:-- TERMINAL --}                                    |
      ]])
      eq({ 22, 6 }, exec_lua('return _G.cursor'))
    end)

    it('does not cause hang in vim.wait() #32753', function()
      local screen = Screen.new(50, 10)

      exec_lua(function()
        local term = vim.api.nvim_open_term(0, {})

        -- Write OSC sequence with pending scrollback. TermRequest will
        -- reschedule itself onto an event queue until the pending scrollback is
        -- processed (i.e. the terminal is refreshed).
        vim.api.nvim_chan_send(term, string.format('%s\027]133;;\007', string.rep('a\n', 100)))

        -- vim.wait() drains the event queue. The terminal won't be refreshed
        -- until the event queue is empty. This test ensures that TermRequest
        -- does not continuously reschedule itself onto the same event queue,
        -- causing an infinite loop.
        vim.wait(100)
      end)

      screen:expect([[
        ^a                                                 |
        a                                                 |*8
                                                          |
      ]])
    end)
  end)

  it('no heap-buffer-overflow when using jobstart("echo",{term=true}) #3161', function()
    local testfilename = 'Xtestfile-functional-terminal-buffers_spec'
    write_file(testfilename, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaa')
    finally(function()
      os.remove(testfilename)
    end)
    feed_command('edit ' .. testfilename)
    -- Move cursor away from the beginning of the line
    feed('$')
    -- Let jobstart(…,{term=true}) modify the buffer
    feed_command([[call jobstart("echo", {'term':v:true})]])
    assert_alive()
    feed_command('bdelete!')
  end)

  it('no heap-buffer-overflow when sending long line with nowrap #11548', function()
    feed_command('set nowrap')
    feed_command('autocmd TermOpen * startinsert')
    feed_command('call feedkeys("4000ai\\<esc>:terminal!\\<cr>")')
    assert_alive()
  end)

  it('truncates the size of grapheme clusters', function()
    local chan = api.nvim_open_term(0, {})
    local composing = ('a̳'):sub(2)
    api.nvim_chan_send(chan, 'a' .. composing:rep(20))
    retry(nil, nil, function()
      eq('a' .. composing:rep(14), api.nvim_get_current_line())
    end)
  end)

  it('handles extended grapheme clusters', function()
    local screen = Screen.new(50, 7)
    feed 'i'
    local chan = api.nvim_open_term(0, {})
    api.nvim_chan_send(chan, '🏴‍☠️ yarrr')
    screen:expect([[
      🏴‍☠️ yarrr^                                          |
                                                        |*5
      {5:-- TERMINAL --}                                    |
    ]])
    eq('🏴‍☠️ yarrr', api.nvim_get_current_line())
  end)

  it('handles split UTF-8 sequences #16245', function()
    local screen = Screen.new(50, 7)
    fn.jobstart({ testprg('shell-test'), 'UTF-8' }, { term = true })
    screen:expect([[
      ^å                                                 |
      ref: å̲                                            |
      1: å̲                                              |
      2: å̲                                              |
      3: å̲                                              |
                                                        |*2
    ]])
  end)

  it('handles unprintable chars', function()
    local screen = Screen.new(50, 7)
    feed 'i'
    local chan = api.nvim_open_term(0, {})
    api.nvim_chan_send(chan, '\239\187\191') -- '\xef\xbb\xbf'
    screen:expect([[
      {18:<feff>}^                                            |
                                                        |*5
      {5:-- TERMINAL --}                                    |
    ]])
    eq('\239\187\191', api.nvim_get_current_line())
  end)

  it("handles bell respecting 'belloff' and 'visualbell'", function()
    local screen = Screen.new(50, 7)
    local chan = api.nvim_open_term(0, {})

    command('set belloff=')
    api.nvim_chan_send(chan, '\a')
    screen:expect(function()
      eq({ true, false }, { screen.bell, screen.visual_bell })
    end)
    screen.bell = false

    command('set visualbell')
    api.nvim_chan_send(chan, '\a')
    screen:expect(function()
      eq({ false, true }, { screen.bell, screen.visual_bell })
    end)
    screen.visual_bell = false

    command('set belloff=term')
    api.nvim_chan_send(chan, '\a')
    screen:expect({
      condition = function()
        eq({ false, false }, { screen.bell, screen.visual_bell })
      end,
      unchanged = true,
    })

    command('set belloff=all')
    api.nvim_chan_send(chan, '\a')
    screen:expect({
      condition = function()
        eq({ false, false }, { screen.bell, screen.visual_bell })
      end,
      unchanged = true,
    })
  end)
end)

describe('on_lines does not emit out-of-bounds line indexes when', function()
  before_each(function()
    clear()
    exec_lua([[
      function _G.register_callback(bufnr)
        _G.cb_error = ''
        vim.api.nvim_buf_attach(bufnr, false, {
          on_lines = function(_, bufnr, _, firstline, _, _)
            local status, msg = pcall(vim.api.nvim_buf_get_offset, bufnr, firstline)
            if not status then
              _G.cb_error = msg
            end
          end
        })
      end
    ]])
  end)

  it('creating a terminal buffer #16394', function()
    feed_command('autocmd TermOpen * ++once call v:lua.register_callback(str2nr(expand("<abuf>")))')
    feed_command('terminal')
    sleep(500)
    eq('', exec_lua([[return _G.cb_error]]))
  end)

  it('deleting a terminal buffer #16394', function()
    feed_command('terminal')
    sleep(500)
    feed_command('lua _G.register_callback(0)')
    feed_command('bdelete!')
    eq('', exec_lua([[return _G.cb_error]]))
  end)
end)

describe('terminal input', function()
  before_each(function()
    clear()
    exec_lua([[
      _G.input_data = ''
      vim.api.nvim_open_term(0, { on_input = function(_, _, _, data)
        _G.input_data = _G.input_data .. data
      end })
    ]])
    feed('i')
    poke_eventloop()
  end)

  it('<C-Space> is sent as NUL byte', function()
    feed('aaa<C-Space>bbb')
    eq('aaa\0bbb', exec_lua([[return _G.input_data]]))
  end)

  it('unknown special keys are not sent', function()
    feed('aaa<Help>bbb')
    eq('aaabbb', exec_lua([[return _G.input_data]]))
  end)
end)

describe('terminal input', function()
  it('sends various special keys with modifiers', function()
    clear()
    local screen = tt.setup_child_nvim({
      '-u',
      'NONE',
      '-i',
      'NONE',
      '--cmd',
      'colorscheme vim',
      '--cmd',
      'set notermguicolors',
      '-c',
      'while 1 | redraw | echo keytrans(getcharstr(-1, #{simplify: 0})) | endwhile',
    })
    screen:expect([[
      ^                                                  |
      {4:~                                                 }|*3
      {5:[No Name]                       0,0-1          All}|
                                                        |
      {3:-- TERMINAL --}                                    |
    ]])
    local keys = {
      '<Tab>',
      '<CR>',
      '<Esc>',
      '<M-Tab>',
      '<M-CR>',
      '<M-Esc>',
      '<BS>',
      '<S-Tab>',
      '<Insert>',
      '<Del>',
      '<PageUp>',
      '<PageDown>',
      '<S-Up>',
      '<C-Up>',
      '<Up>',
      '<S-Down>',
      '<C-Down>',
      '<Down>',
      '<S-Left>',
      '<C-Left>',
      '<Left>',
      '<S-Right>',
      '<C-Right>',
      '<Right>',
      '<S-Home>',
      '<C-Home>',
      '<Home>',
      '<S-End>',
      '<C-End>',
      '<End>',
      '<C-LeftMouse><0,0>',
      '<C-LeftDrag><0,1>',
      '<C-LeftRelease><0,1>',
      '<2-LeftMouse><0,1>',
      '<2-LeftDrag><0,0>',
      '<2-LeftRelease><0,0>',
      '<M-MiddleMouse><0,0>',
      '<M-MiddleDrag><0,1>',
      '<M-MiddleRelease><0,1>',
      '<2-MiddleMouse><0,1>',
      '<2-MiddleDrag><0,0>',
      '<2-MiddleRelease><0,0>',
      '<S-RightMouse><0,0>',
      '<S-RightDrag><0,1>',
      '<S-RightRelease><0,1>',
      '<2-RightMouse><0,1>',
      '<2-RightDrag><0,0>',
      '<2-RightRelease><0,0>',
      '<S-X1Mouse><0,0>',
      '<S-X1Drag><0,1>',
      '<S-X1Release><0,1>',
      '<2-X1Mouse><0,1>',
      '<2-X1Drag><0,0>',
      '<2-X1Release><0,0>',
      '<S-X2Mouse><0,0>',
      '<S-X2Drag><0,1>',
      '<S-X2Release><0,1>',
      '<2-X2Mouse><0,1>',
      '<2-X2Drag><0,0>',
      '<2-X2Release><0,0>',
      '<S-ScrollWheelUp>',
      '<S-ScrollWheelDown>',
      '<ScrollWheelUp>',
      '<ScrollWheelDown>',
      '<S-ScrollWheelLeft>',
      '<S-ScrollWheelRight>',
      '<ScrollWheelLeft>',
      '<ScrollWheelRight>',
    }
    -- FIXME: The escape sequence to enable kitty keyboard mode doesn't work on Windows
    if not is_os('win') then
      table.insert(keys, '<C-I>')
      table.insert(keys, '<C-M>')
      table.insert(keys, '<C-[>')
    end
    for _, key in ipairs(keys) do
      feed(key)
      screen:expect(([[
                                                          |
        {4:~                                                 }|*3
        {5:[No Name]                       0,0-1          All}|
        %s^ {MATCH: *}|
        {3:-- TERMINAL --}                                    |
      ]]):format(key:gsub('<%d+,%d+>$', '')))
    end
  end)
end)

if is_os('win') then
  describe(':terminal in Windows', function()
    local screen

    before_each(function()
      clear()
      feed_command('set modifiable swapfile undolevels=20')
      poke_eventloop()
      local cmd = { 'cmd.exe', '/K', 'PROMPT=$g$s' }
      screen = tt.setup_screen(nil, cmd)
    end)

    it('"put" operator sends data normally', function()
      feed('<c-\\><c-n>G')
      feed_command('let @a = ":: tty ready"')
      feed_command('let @a = @a . "\\n:: appended " . @a . "\\n\\n"')
      feed('"ap"ap')
      screen:expect([[
                                                        |
      > :: tty ready                                    |
      > :: appended :: tty ready                        |
      > :: tty ready                                    |
      > :: appended :: tty ready                        |
      ^>                                                 |
      :let @a = @a . "\n:: appended " . @a . "\n\n"     |
      ]])
      -- operator count is also taken into consideration
      feed('3"ap')
      screen:expect([[
      > :: appended :: tty ready                        |
      > :: tty ready                                    |
      > :: appended :: tty ready                        |
      > :: tty ready                                    |
      > :: appended :: tty ready                        |
      ^>                                                 |
      :let @a = @a . "\n:: appended " . @a . "\n\n"     |
      ]])
    end)

    it('":put" command sends data normally', function()
      feed('<c-\\><c-n>G')
      feed_command('let @a = ":: tty ready"')
      feed_command('let @a = @a . "\\n:: appended " . @a . "\\n\\n"')
      feed_command('put a')
      screen:expect([[
                                                        |
      > :: tty ready                                    |
      > :: appended :: tty ready                        |
      >                                                 |
                                                        |
      ^                                                  |
      :put a                                            |
      ]])
      -- line argument is only used to move the cursor
      feed_command('6put a')
      screen:expect([[
                                                        |
      > :: tty ready                                    |
      > :: appended :: tty ready                        |
      > :: tty ready                                    |
      > :: appended :: tty ready                        |
      ^>                                                 |
      :6put a                                           |
      ]])
    end)
  end)
end

describe('termopen() (deprecated alias to `jobstart(…,{term=true})`)', function()
  before_each(clear)

  it('disallowed when textlocked and in cmdwin buffer', function()
    command("autocmd TextYankPost <buffer> ++once call termopen('foo')")
    matches(
      'Vim%(call%):E565: Not allowed to change text or change window$',
      pcall_err(command, 'normal! yy')
    )

    feed('q:')
    eq(
      'Vim:E11: Invalid in command-line window; <CR> executes, CTRL-C quits',
      pcall_err(fn.termopen, 'bar')
    )
  end)

  describe('$COLORTERM value', function()
    if skip(is_os('win'), 'Not applicable for Windows') then
      return
    end

    before_each(function()
      -- Outer value should never be propagated to :terminal
      fn.setenv('COLORTERM', 'wrongvalue')
    end)

    local function test_term_colorterm(expected, opts)
      local screen = Screen.new(50, 4)
      fn.termopen({
        nvim_prog,
        '-u',
        'NONE',
        '-i',
        'NONE',
        '--headless',
        '-c',
        'echo $COLORTERM | quit',
      }, opts)
      screen:expect(([[
        ^%s{MATCH:%%s+}|
        [Process exited 0]                                |
                                                          |*2
      ]]):format(expected))
    end

    describe("with 'notermguicolors'", function()
      before_each(function()
        command('set notermguicolors')
      end)
      it('is empty by default', function()
        test_term_colorterm('')
      end)
      it('can be overridden', function()
        test_term_colorterm('expectedvalue', { env = { COLORTERM = 'expectedvalue' } })
      end)
    end)

    describe("with 'termguicolors'", function()
      before_each(function()
        command('set termguicolors')
      end)
      it('is "truecolor" by default', function()
        test_term_colorterm('truecolor')
      end)
      it('can be overridden', function()
        test_term_colorterm('expectedvalue', { env = { COLORTERM = 'expectedvalue' } })
      end)
    end)
  end)
end)
