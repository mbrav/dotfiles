return {
  {
    "williamboman/mason.nvim",
    enabled = true,
    lazy = false,
    opts = {
      ensure_installed = {
        "shellcheck",
        "shfmt",
        "flake8",
        "cpplint",
      },
    },
  },
  {
    "williamboman/mason-lspconfig.nvim",
    enabled = true,
    lazy = false,
    opts = {
      ensure_installed = {
        "lua_ls",
        "bashls",
        "rust_analyzer",
        "docker_compose_language_service",
        "dockerls",
        "harper_ls",
        "html",
      },
    },
  },
  {
    "jay-babu/mason-null-ls.nvim",
    enabled = true,
    lazy = false,
    opts = {
      ensure_installed = {
        "ansible-lint",
        "shellcheck",
        "black",
        -- "pyright",
        "ruff",
        "markdownlint",
        "jq",
        "jsonlint",
        "yamlfmt",
        "yamllint",
        "sqlfmt",
        -- "rustfmt", -- Installed via rustup now
        -- "codespell"
      },
    },
  },
  {
    "jay-babu/mason-nvim-dap.nvim",
    enabled = true,
    lazy = false,
    opts = {
      ensure_installed = {
        "bash",
        "python",
        "codelldb",
      },
    },
  },
}
