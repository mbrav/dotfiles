return {
  {
    "linux-cultist/venv-selector.nvim",
    dependencies = {
      "neovim/nvim-lspconfig",
      "mfussenegger/nvim-dap",
      "mfussenegger/nvim-dap-python", --optional
      { "nvim-telescope/telescope.nvim", branch = "master", dependencies = { "nvim-lua/plenary.nvim" } },
    },
    lazy = false,
    branch = "main",
    keys = {
      { ",v", "<cmd>VenvSelect<cr>" },
    },
    opts = {
      -- Your settings go here
    },
  },
}
