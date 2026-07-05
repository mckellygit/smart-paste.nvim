local paste = require('smart-paste.paste')

local has_busted = type(describe) == 'function' and type(it) == 'function'

local function group(_name, fn)
  if has_busted then
    describe(_name, fn)
  else
    fn()
  end
end

local function case(_name, fn)
  if has_busted then
    it(_name, fn)
    return
  end

  local ok, err = pcall(fn)
  if not ok then
    error(_name .. ': ' .. tostring(err))
  end
end

local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].expandtab = true
  vim.bo[bufnr].tabstop = 4
  vim.bo[bufnr].shiftwidth = 4
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local function delete_buf(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function get_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function assert_eq(actual, expected, msg)
  if not vim.deep_equal(actual, expected) then
    local actual_text = vim.inspect(actual)
    local expected_text = vim.inspect(expected)
    error((msg or 'assertion failed') .. '\nexpected: ' .. expected_text .. '\nactual: ' .. actual_text)
  end
end

group('charwise_paste', function()
  case(']p pastes single-line charwise content below cursor with smart indent', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('a', 'return x', 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'a',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'def foo():', '    x = 1', '    return x', '' })
    delete_buf(bufnr)
  end)

  case('[p pastes single-line charwise content above cursor with smart indent', function()
    local bufnr = make_buf({ 'def foo():', '    y = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('b', 'return y', 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'b',
      count = 1,
      key = '[p',
      after = false,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'def foo():', '    return y', '    y = 1', '' })
    delete_buf(bufnr)
  end)

  case(']p strips leading whitespace from charwise content before indenting', function()
    local bufnr = make_buf({ 'if true then', '        x = 1', 'end' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('c', '    return x', 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'c',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    local lines = get_lines(bufnr)
    if lines[3] ~= '        return x' then
      delete_buf(bufnr)
      error('expected stripped-and-indented line at target indent')
    end
    delete_buf(bufnr)
  end)

  case(']p converts multi-line charwise content to linewise with preserved relative indent', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('d', { 'if True:', '    pass' }, 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'd',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'def foo():', '    x = 1', '    if True:', '        pass', '' })
    delete_buf(bufnr)
  end)

  case(']p with linewise register follows normal smart linewise path', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('e', { 'item' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'e',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'def foo():', '    x = 1', '    item', '' })
    delete_buf(bufnr)
  end)

  case('[p above a python elif indents into the if block (issue #15)', function()
    -- Regression: `dd` a python if-block body, then `[p` above the `elif`.
    -- The elif line is a keyword scope closer; the paste must target the
    -- enclosing if-block body indent, not the elif's own indent.
    local bufnr = make_buf({ 'if foo:', 'elif baz:', '    blah()' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('m', { '    bar()' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'm',
      count = 1,
      key = '[p',
      after = false,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'if foo:', '    bar()', 'elif baz:', '    blah()' })
    delete_buf(bufnr)
  end)

  case(']p after a lua keyword opener indents into the empty block', function()
    -- Regression: `then` is a keyword scope opener (no trailing brace/colon);
    -- pasting below it into an empty block must indent one level in.
    local bufnr = make_buf({ 'if x then', 'end' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('n', { 'print(1)' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    paste._test_set_state({
      register = 'n',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'if x then', '    print(1)', 'end' })
    delete_buf(bufnr)
  end)

  case('p below a python opener with a trailing comment indents into the block (issue #19)', function()
    -- Regression: an inline comment after the colon hid the opener token, so
    -- the paste landed at column 0 instead of inside the if block.
    local bufnr = make_buf({ 'if foo < bar: # some comment', '    baz()' })
    vim.bo[bufnr].commentstring = '# %s'
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('o', { 'x = 1' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    paste._test_set_state({
      register = 'o',
      count = 1,
      key = 'p',
      after = true,
      follow = false,
      charwise_newline = false,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'if foo < bar: # some comment', '    x = 1', '    baz()' })
    delete_buf(bufnr)
  end)

  case('p below a lua keyword opener with a trailing comment indents into the block (issue #19)', function()
    -- Same defect for keyword openers: `then` followed by an inline `--`
    -- comment must still read as a scope opener.
    local bufnr = make_buf({ 'if x then -- note', 'end' })
    vim.bo[bufnr].commentstring = '-- %s'
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('q', { 'print(1)' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    paste._test_set_state({
      register = 'q',
      count = 1,
      key = 'p',
      after = true,
      follow = false,
      charwise_newline = false,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'if x then -- note', '    print(1)', 'end' })
    delete_buf(bufnr)
  end)

  case('P above a commented elif still indents into the if block (issue #19)', function()
    -- The elif line is a keyword scope closer; a trailing comment on it must
    -- not stop the paste from targeting the enclosing block body indent.
    local bufnr = make_buf({ 'if foo:', 'elif baz: # note', '    blah()' })
    vim.bo[bufnr].commentstring = '# %s'
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('r', { '    bar()' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'r',
      count = 1,
      key = 'P',
      after = false,
      follow = false,
      charwise_newline = false,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'if foo:', '    bar()', 'elif baz: # note', '    blah()' })
    delete_buf(bufnr)
  end)

  case('P above a closer whose opener carries a trailing comment indents into the block (issue #19)', function()
    -- Empty-block closer branch: the opener check runs on the previous line,
    -- so a comment there hid the `:` and the paste stayed at column 0.
    local bufnr = make_buf({ 'if foo: # setup', 'elif baz:', '    blah()' })
    vim.bo[bufnr].commentstring = '# %s'
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('s', { '    bar()' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 's',
      count = 1,
      key = 'P',
      after = false,
      follow = false,
      charwise_newline = false,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'if foo: # setup', '    bar()', 'elif baz:', '    blah()' })
    delete_buf(bufnr)
  end)

  case('p on a full-line comment keeps the current indent and does not error', function()
    -- A comment leader at the start of the line is not a trailing comment;
    -- the heuristics must leave the line alone and paste at its own indent.
    local bufnr = make_buf({ '# just a comment', 'x = 1' })
    vim.bo[bufnr].commentstring = '# %s'
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('t', { 'y = 2' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    paste._test_set_state({
      register = 't',
      count = 1,
      key = 'p',
      after = true,
      follow = false,
      charwise_newline = false,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { '# just a comment', 'y = 2', 'x = 1' })
    delete_buf(bufnr)
  end)

  case(']p with blockwise register falls through to vanilla paste', function()
    local bufnr = make_buf({ 'alpha', 'beta' })
    vim.api.nvim_set_current_buf(bufnr)
    local orig_feedkeys = vim.api.nvim_feedkeys
    local calls = 0
    vim.api.nvim_feedkeys = function(...)
      calls = calls + 1
      return nil
    end

    vim.fn.setreg('f', { 'XX' }, '\0222')
    paste._test_set_state({
      register = 'f',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')

    vim.api.nvim_feedkeys = orig_feedkeys
    if calls ~= 1 then
      delete_buf(bufnr)
      error('expected one vanilla fallback call for blockwise register')
    end
    delete_buf(bufnr)
  end)

  case(']p count repeats charwise-to-newline insertion', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('g', 'return z', 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'g',
      count = 2,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')

    local count = 0
    for _, line in ipairs(get_lines(bufnr)) do
      if line == '    return z' then
        count = count + 1
      end
    end
    if count ~= 2 then
      delete_buf(bufnr)
      error('expected two inserted copies for count=2')
    end
    delete_buf(bufnr)
  end)

  case(']p preserves trailing whitespace for charwise content', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('h', 'return x   ', 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'h',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    local lines = get_lines(bufnr)
    if lines[3] ~= '    return x   ' then
      delete_buf(bufnr)
      error('expected trailing whitespace to be preserved')
    end
    delete_buf(bufnr)
  end)

  case(']p drops trailing blank from a line-boundary (v$) charwise selection', function()
    -- A `v$` selection on a non-final line captures the trailing newline, so the
    -- charwise register gains a trailing empty entry. It must not paste as a
    -- stray blank line.
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('k', { 'return x', '' }, 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'k',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'def foo():', '    x = 1', '    return x', '' })
    delete_buf(bufnr)
  end)

  case(']p preserves relative indent of a multi-line block (charwise mid-line select)', function()
    -- A `^v...y` selection of an indented block drops line 1's whitespace but
    -- keeps the inner lines' absolute indent. The pasted sibling must match the
    -- original block's structure, not be over-indented by its base indent.
    local bufnr = make_buf({
      '<Wrapper>',
      '    <Group>',
      '        <Item />',
      '    </Group>',
      '</Wrapper>',
    })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('l', { '<Group>', '        <Item />', '    </Group>' }, 'v')
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    paste._test_set_state({
      register = 'l',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), {
      '<Wrapper>',
      '    <Group>',
      '        <Item />',
      '    </Group>',
      '    <Group>',
      '        <Item />',
      '    </Group>',
      '</Wrapper>',
    })
    delete_buf(bufnr)
  end)

  case(']p levels sibling lines when the first charwise line is not an opener (issue #17)', function()
    -- A mid-line charwise yank of two sibling statements drops line 1's
    -- indent; the old rebase always nested the inner lines under line 1,
    -- over-indenting baz() by the block's original base.
    local bufnr = make_buf({ 'x = 1', '' })
    vim.bo[bufnr].commentstring = '# %s'
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('j', { 'bar()', '    baz()' }, 'v')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    paste._test_set_state({
      register = 'j',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'x = 1', 'bar()', 'baz()', '' })
    delete_buf(bufnr)
  end)

  case(']p keeps charwise siblings level at an indented target (issue #17)', function()
    -- Same sibling block pasted inside a function body: both lines must land
    -- at the body indent, not one level apart.
    local bufnr = make_buf({ 'def f():', '    x = 1', '' })
    vim.bo[bufnr].commentstring = '# %s'
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('u', { 'bar()', '    baz()' }, 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'u',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'def f():', '    x = 1', '    bar()', '    baz()', '' })
    delete_buf(bufnr)
  end)

  case(']p keeps a blank first charwise line blank instead of padding it', function()
    -- A charwise yank starting on an empty line carries no sibling evidence;
    -- the first line must stay blank, not become a whitespace-only line with
    -- the inner lines flattened to it.
    local bufnr = make_buf({ 'x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('w', { '', '    baz()', '' }, 'v')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    paste._test_set_state({
      register = 'w',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'x = 1', '', '    baz()', '' })
    delete_buf(bufnr)
  end)

  case(']p still nests inner lines under a brace opener first line', function()
    -- An opener-looking first line keeps the nesting guess: the body stays one
    -- level inside the block after the rebase.
    local bufnr = make_buf({ 'x = 1', '' })
    vim.bo[bufnr].commentstring = '// %s'
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('v', { 'function foo() {', '    body()' }, 'v')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    paste._test_set_state({
      register = 'v',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'x = 1', 'function foo() {', '    body()', '' })
    delete_buf(bufnr)
  end)

  case(']p with empty charwise register does not crash', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('i', '', 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'i',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })

    local ok, err = pcall(paste.do_paste, 'line')
    if not ok then
      delete_buf(bufnr)
      error('expected empty charwise register to be handled safely: ' .. tostring(err))
    end
    delete_buf(bufnr)
  end)
end)
