return {
  -- add more treesitter parsers
  {
    "nvim-treesitter/nvim-treesitter",
    enabled = true,
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      ensure_installed = {
        "bash",
        "html",
        "json",
        "lua",
        "markdown",
        "markdown_inline",
        "python",
        "regex",
        "vim",
        "yaml",
        "terraform",
        "hcl",
      },
    },
  },
}
