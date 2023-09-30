return {
  {
    "numToStr/Comment.nvim",
    enabled = true,
    lazy = false,
    keys = {
      {
        "<leader>n",
        function() require("Comment.api").toggle.linewise.count(vim.v.count > 0 and vim.v.count or 1) end,
        "Toggle Comment Line",
      },
    },
    opts = {
      mappings = {
        ---Line-comment keymap
        basic = false,
        ---Block-comment keymap
        extra = false,
      },
    },
  },
}
