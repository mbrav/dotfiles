return {
  {
    "neovim/nvim-lspconfig",
    init = function()
      vim.lsp.config("gopls", {
        settings = {
          gopls = {
            env = { GOEXPERIMENT = "simd" },
          },
        },
      })
    end,
  },
}
