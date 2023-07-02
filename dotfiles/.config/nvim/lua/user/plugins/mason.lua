-- customize mason plugins
return {
  -- use mason-lspconfig to configure LSP installations
  {
    "williamboman/mason-lspconfig.nvim",
    -- overrides `require("mason-lspconfig").setup(...)`
    opts = {
      ensure_installed = { "lua_ls", "bashls", "rust_analyzer", "docker_compose_language_service", "dockerls", "html" },
    },
  },
  -- use mason-null-ls to configure Formatters/Linter installation for null-ls sources
  {
    "jay-babu/mason-null-ls.nvim",
    -- overrides `require("mason-null-ls").setup(...)`
    opts = {
      ensure_installed = { "ansible-lint", "shellcheck", "black", "pylsp", "markdownlint", "jq", "jsonlint", "yamlfmt",
        "sqlfmt",
        "rustfmt", "codespell" },
    },
  },
  {
    "jay-babu/mason-nvim-dap.nvim",
    -- overrides `require("mason-nvim-dap").setup(...)`
    opts = {
      ensure_installed = { "bash", "python", "codelldb" },
      -- ensure_installed = { "bash", "codelldb" },
    },
  },
}
