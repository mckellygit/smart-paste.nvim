--- @class SmartPaste.Heuristics
local M = {}

--- Escape Lua pattern magic characters in a plain string.
--- Needed because comment leaders like `--` contain pattern magic (`-`).
--- @param text string
--- @return string escaped
local function escape_pattern(text)
  return (text:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%0'))
end

--- Strip a trailing inline comment from a line using the buffer's
--- `commentstring` (e.g. `# %s` for python, `-- %s` for lua).
--- Only a comment leader preceded by whitespace is stripped, which keeps
--- false positives low (a leader character mid-word is left alone).
--- @param line string
--- @param bufnr integer
--- @return string line
local function strip_trailing_comment(line, bufnr)
  local commentstring = vim.bo[bufnr].commentstring or ''
  local leader = vim.trim(commentstring:match('^(.-)%%s') or '')
  if leader == '' then
    return line
  end
  return (line:gsub('%s+' .. escape_pattern(leader) .. '.*$', ''))
end

--- Heuristic: line opens an HTML/Vue-like tag block.
--- Supports single-line tag openers and multiline opener tails (`>` line).
--- A complete element closed on the same line (e.g. JSX `<li>x</li>`) is not an opener.
--- @param line string
--- @return boolean
local function looks_like_tag_opener(line)
  if line:match('^%s*>%s*$') then
    return true
  end
  if line:match('^%s*<[%w:_-]') and line:match('>%s*$') and not line:match('/>%s*$') and not line:match('</') then
    return true
  end
  return false
end

--- Heuristic: line closes an HTML/Vue-like tag block.
--- @param line string
--- @return boolean
local function looks_like_tag_closer(line)
  return line:match('^%s*</[%w:_-][^>]*>%s*$') ~= nil
end

local SCOPE_OPENER_KEYWORDS = { 'then', 'do', 'else', 'elseif', 'repeat', 'function' }
local SCOPE_CLOSER_KEYWORDS = { 'end', 'elif', 'else', 'elseif', 'catch', 'finally' }

--- Heuristic: line ends with an opener token for block-like constructs.
--- @param line string
--- @return boolean
local function looks_like_scope_opener(line)
  if line:match('[%{%[%(:]%s*$') then
    return true
  end
  if looks_like_tag_opener(line) then
    return true
  end
  -- Lua patterns have no alternation; test each keyword separately.
  for _, keyword in ipairs(SCOPE_OPENER_KEYWORDS) do
    if line:match('%f[%a]' .. keyword .. '%s*$') then
      return true
    end
  end
  return false
end

--- Heuristic: line begins with a closing token for block-like constructs.
--- @param line string
--- @return boolean
local function looks_like_scope_closer(line)
  if line:match('^%s*[%}%]%)]') then
    return true
  end
  if looks_like_tag_closer(line) then
    return true
  end
  -- Lua patterns have no alternation; test each keyword separately.
  for _, keyword in ipairs(SCOPE_CLOSER_KEYWORDS) do
    if line:match('^%s*' .. keyword .. '%f[%A]') then
      return true
    end
  end
  return false
end

--- Whether a line opens a block-like scope, ignoring any trailing inline
--- comment (e.g. `if foo < bar: # note` still reads as an opener).
--- @param line string
--- @param bufnr? integer Buffer whose `commentstring` applies (defaults to current buffer)
--- @return boolean
function M.is_scope_opener(line, bufnr)
  return looks_like_scope_opener(strip_trailing_comment(line, bufnr or 0))
end

--- Whether a line closes a block-like scope, ignoring any trailing inline
--- comment (e.g. `end -- note` still reads as a closer).
--- @param line string
--- @param bufnr? integer Buffer whose `commentstring` applies (defaults to current buffer)
--- @return boolean
function M.is_scope_closer(line, bufnr)
  return looks_like_scope_closer(strip_trailing_comment(line, bufnr or 0))
end

return M
