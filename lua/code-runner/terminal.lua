local M = {}

-- Persistent bottom terminal state (shared by toggle and exec)
local term_buf = nil
local term_win = nil

--- Close the current terminal buffer and its windows
local function close_term()
  if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
    for _, w in ipairs(vim.fn.win_findbuf(term_buf)) do
      vim.api.nvim_win_close(w, true)
    end
    vim.api.nvim_buf_delete(term_buf, { force = true })
  end
  term_buf = nil
  term_win = nil
end

--- Create a new bottom terminal running `cmd` (or a shell if nil)
---@param config table
---@param cmd string|nil
local function create_term(config, cmd)
  local term_cmd = "botright " .. config.term_height .. "split | term"
  if cmd then
    term_cmd = term_cmd .. " " .. cmd
  end
  vim.cmd(term_cmd)
  term_buf = vim.api.nvim_get_current_buf()
  term_win = vim.api.nvim_get_current_win()
end

--- Execute a shell command in the bottom terminal (closes old term, creates new)
---@param cmd string
---@param config table
function M.exec(cmd, config)
  close_term()
  create_term(config, cmd)
end

--- Toggle a persistent bottom terminal
---@param config table
function M.toggle(config)
  -- terminal window is visible -> hide it
  if term_win and vim.api.nvim_win_is_valid(term_win) then
    vim.api.nvim_win_hide(term_win)
    term_win = nil
    return
  end

  -- buffer still alive -> re-show it
  if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
    vim.cmd("botright " .. config.term_height .. "split")
    term_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(term_win, term_buf)
    vim.cmd("startinsert")
    return
  end

  -- create new terminal (interactive shell)
  create_term(config, nil)
end

return M
