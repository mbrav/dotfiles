-- Global markdownlint-cli2 config that disables MD013 line length. Without
-- --config, markdownlint-cli2 only finds a config in the cwd or the file's dir
local config = vim.fn.stdpath "config" .. "/.markdownlint-cli2.yaml"

-- lang.markdown runs markdownlint-cli2 twice, through nvim-lint and through the
-- none-ls extra, so both need the config or MD013 still shows up
return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          args = { "--config", config, "-" },
        },
      },
    },
  },
  {
    "nvimtools/none-ls.nvim",
    optional = true,
    opts = function(_, opts)
      local nls = require "null-ls"
      for i, source in ipairs(opts.sources or {}) do
        if source.name == "markdownlint-cli2" then
          opts.sources[i] = nls.builtins.diagnostics.markdownlint_cli2.with {
            extra_args = { "--config", config },
          }
        end
      end
    end,
  },
}
