return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        -- Use terraform_fmt for HCL files (overrides LazyVim default of packer_fmt)
        -- Also applies to .alloy files since they are mapped to the hcl filetype
        hcl = { "terraform_fmt" },
      },
    },
  },
}
