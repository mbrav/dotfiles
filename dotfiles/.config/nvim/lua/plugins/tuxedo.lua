-- Floating window around the `tuxedo` todo.txt TUI (needs the binary on PATH).
return {
  {
    "IogaMaster/tuxedo.nvim",
    lazy = true,
    cmd = { "Tuxedo" },
    keys = {
      { "<leader>td", "<cmd>Tuxedo<cr>", desc = "Tuxedo (todo.txt)" },
    },
    opts = {
      -- The plugin would write an empty todo.txt at the git root of whatever
      -- repo you open it from, but TODO_FILE (set in scripts/_aliases) wins, so
      -- the TUI never reads that file — it is pure litter in every repo.
      create_todo_file = false,
      width_ratio = 0.95,
      height_ratio = 0.80,
    },
    config = function(_, opts) require("tuxedo").setup(opts) end,
  },
}
