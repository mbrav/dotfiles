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
      -- "multi", not "takeover": in takeover the first Neovim owns the server
      -- and a second one only publishes into its workspace — the join path
      -- never opens a browser, so starting a preview in another project looks
      -- like nothing happened, and quitting the first Neovim kills everyone's
      -- preview. multi gives each instance its own server, port and tab.
      instance_mode = "multi",
      port = 0, -- OS-assigned; fixed ports collide across instances
      default_theme = "dark",
    },
  },
}
