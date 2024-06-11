return {
  -- add more treesitter parsers
  {
    "nvim-treesitter/nvim-treesitter",
    enabled = true,
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      ensure_installed = {
        "bash",
        "rust",
        "html",
        "json",
        "lua",
        "markdown",
        "markdown_inline",
        "python",
        "regex",
        "toml",
        "vim",
        "yaml",
        "terraform",
        "hcl",
        "c",
      },
    },
  },
}
