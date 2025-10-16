return {
  {
    "mason-org/mason.nvim",
    enabled = true,
    opts = {
      ensure_installed = {
        "bash-language-server",
        "shellcheck",
        "dotenv-linter",
        "isort",
        "yamlfmt",
        "yamllint",
      },
    },
  },
}
