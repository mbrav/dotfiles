return {
  { "iamcco/markdown-preview.nvim", enabled = false },

  {
    "selimacerbas/mdkite.nvim",
    dependencies = { "selimacerbas/kitehost.nvim" }, -- pure-Lua HTTP server, needs v2.0.0+
    cmd = { "MdKite" },
    ft = { "markdown", "mermaid" },
    keys = {
      { "<leader>cp", "<cmd>MdKite toggle<cr>", ft = "markdown", desc = "Markdown Preview" },
    },
    opts = {
      -- One browser tab reused across files, rather than a tab per buffer.
      instance_mode = "takeover",
      default_theme = "dark",
    },
  },
}
