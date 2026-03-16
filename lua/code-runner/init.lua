local runner = require("code-runner.runner")
local terminal = require("code-runner.terminal")

local M = {}

M.defaults = {
  use_terminal = true,
  term_height = 15,
  cpp = {
    single_file_cmd = "clang++ -std=c++23 -stdlib=libc++ -o /tmp/{name} {file} && /tmp/{name}",
    test_dir = "test",
    src_dir = "src",
  },
  filetype_cmds = {
    javascript = "node {file}",
  },
  keymaps = {
    toggle_term = "<leader>j",
  },
}

M.config = {}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})

  vim.api.nvim_create_user_command("Run", function() runner.run(M.config) end, {})
  vim.api.nvim_create_user_command("Test", function() runner.test(M.config) end, {})
  vim.api.nvim_create_user_command("ToggleRunMode", function()
    M.config.use_terminal = not M.config.use_terminal
    vim.notify("Runner: " .. (M.config.use_terminal and "terminal" or "bang"))
  end, {})

  local km = M.config.keymaps
  if km.toggle_term then
    vim.keymap.set("n", km.toggle_term, function() terminal.toggle(M.config) end, { desc = "Toggle bottom terminal" })
    vim.keymap.set("t", km.toggle_term, function() terminal.toggle(M.config) end, { desc = "Toggle bottom terminal" })
  end
end

return M
