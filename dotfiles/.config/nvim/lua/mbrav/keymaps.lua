vim.api.nvim_set_keymap("n", "<leader>W", ":w<CR>", { desc = "Save File" }) -- increment
vim.api.nvim_set_keymap("i", "jj", "<Esc>", { noremap = false })
vim.api.nvim_set_keymap("i", "jk", "<Esc>", { noremap = false })
