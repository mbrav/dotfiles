-- Floating window around the `tuxedo` todo.txt TUI (needs the binary on PATH).
return {
  {
    "IogaMaster/tuxedo.nvim",
    lazy = true,
    cmd = { "Tuxedo" },
    keys = {
      { "<leader>td", "<cmd>Tuxedo<cr>", desc = "Tuxedo (todo.txt)" },
    },
    -- plugin/tuxedo.lua already calls setup() with the defaults; opts only
    -- overrides them, so config = true is enough to keep lazy happy.
    opts = {
      create_todo_file = true,
      width_ratio = 0.95,
      height_ratio = 0.80,
    },
    config = function(_, opts) require("tuxedo").setup(opts) end,
  },
}
