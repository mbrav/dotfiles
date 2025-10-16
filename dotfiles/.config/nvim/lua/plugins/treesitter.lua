return {
  -- add more treesitter parsers
  {
    "nvim-treesitter/nvim-treesitter",
    enabled = true,
    lazy = true,
    opts = {
      ensure_installed = {
        "bash",
        "html",
        "javascript",
        "json",
        "lua",
        "markdown",
        "markdown_inline",
        "python",
        "query",
        "regex",
        "tsx",
        "vim",
        "yaml",
      },
    },
  },
}
