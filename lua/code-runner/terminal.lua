local M = {}

-- Persistent bottom terminal state
local term_buf = nil
local term_win = nil

-- Run-command terminal (reused across :Run calls)
local run_buf = nil

--- Execute a shell command via split terminal (reuses previous run terminal)
---@param cmd string
---@param config table
function M.exec(cmd, config)
  -- close previous run terminal if it exists
  if run_buf and vim.api.nvim_buf_is_valid(run_buf) then
    for _, w in ipairs(vim.fn.win_findbuf(run_buf)) do
      vim.api.nvim_win_close(w, true)
    end
    vim.api.nvim_buf_delete(run_buf, { force = true })
    run_buf = nil
  end

  if config.use_terminal then
    vim.cmd("botright " .. config.term_height .. "split | term " .. cmd)
    run_buf = vim.api.nvim_get_current_buf()
  else
    vim.cmd("!" .. vim.fn.escape(cmd, "%#!"))
  end
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

  -- create new terminal
  vim.cmd("botright " .. config.term_height .. "split | term")
  term_buf = vim.api.nvim_get_current_buf()
  term_win = vim.api.nvim_get_current_win()
end

return M
