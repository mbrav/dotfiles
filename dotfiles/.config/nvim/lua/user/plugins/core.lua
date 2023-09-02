return {
  -- customize alpha options
  {
    "goolord/alpha-nvim",
    opts = function(_, opts)
      -- customize the dashboard header
      -- https://www.patorjk.com/software/taag/#p=display&h=0&v=0&f=ANSI%20Regular
      opts.section.header.val = {
        " ",
        "███    ███ ██████  ██████   █████  ██    ██ ",
        "████  ████ ██   ██ ██   ██ ██   ██ ██    ██ ",
        "██ ████ ██ ██████  ██████  ███████ ██    ██ ",
        "██  ██  ██ ██   ██ ██   ██ ██   ██  ██  ██  ",
        "██      ██ ██████  ██   ██ ██   ██   ████   ",
        "    Maximum Bit Rate Autonomous Vehicle     ",
        " ",
        "          ██    ██ ██ ███    ███            ",
        "          ██    ██ ██ ████  ████            ",
        "          ██    ██ ██ ██ ████ ██            ",
        "           ██  ██  ██ ██  ██  ██            ",
        "            ████   ██ ██      ██            ",
        " ",
      }
      return opts
    end,
  },
  -- You can also easily customize additional setup of plugins that is outside of the plugin's setup call
  {
    "nvim-neo-tree/neo-tree.nvim",
    config = function(_, opts)
      opts.filesystem.filtered_items = {
        visible = true,
        show_hidden_count = true,
        hide_dotfiles = false,
        hide_gitignored = false,
        hide_by_name = {
          '.git',
          -- '.DS_Store',
          -- 'thumbs.db',
        },
        never_show = {},
      }
      return opts
    end,
  },
  {
    "rebelot/heirline.nvim",
    opts = function(_, opts)
      local status = require("astronvim.utils.status")
      -- local wakatime = require("user.plugins.wakatime")
      opts.statusline = {
        hl = { fg = "fg", bg = "bg" },
        status.component.mode { mode_text = { padding = { left = 1, right = 1 } } }, -- add the mode text
        status.component.git_branch(),
        status.component.file_info { filetype = {}, filename = false, file_modified = false },
        status.component.git_diff(),
        status.component.diagnostics(),
        status.component.fill(),
        status.component.cmd_info(),
        status.component.fill(),
        status.component.lsp(),
        status.component.treesitter(),
        status.component.nav(),
        -- remove the 2nd mode indicator on the right
      }
      -- return the final configuration table
      return opts
    end,
  },
  -- You can disable default plugins as follows:
  -- { "max397574/better-escape.nvim", enabled = false },
  --
  -- You can also easily customize additional setup of plugins that is outside of the plugin's setup call
  -- {
  --   "L3MON4D3/LuaSnip",
  --   config = function(plugin, opts)
  --     require "plugins.configs.luasnip"(plugin, opts) -- include the default astronvim config that calls the setup call
  --     -- add more custom luasnip configuration such as filetype extend or custom snippets
  --     local luasnip = require "luasnip"
  --     luasnip.filetype_extend("javascript", { "javascriptreact" })
  --   end,
  -- },
  -- {
  --   "windwp/nvim-autopairs",
  --   config = function(plugin, opts)
  --     require "plugins.configs.nvim-autopairs"(plugin, opts) -- include the default astronvim config that calls the setup call
  --     -- add more custom autopairs configuration such as custom rules
  --     local npairs = require "nvim-autopairs"
  --     local Rule = require "nvim-autopairs.rule"
  --     local cond = require "nvim-autopairs.conds"
  --     npairs.add_rules(
  --       {
  --         Rule("$", "$", { "tex", "latex" })
  --           -- don't add a pair if the next character is %
  --           :with_pair(cond.not_after_regex "%%")
  --           -- don't add a pair if  the previous character is xxx
  --           :with_pair(
  --             cond.not_before_regex("xxx", 3)
  --           )
  --           -- don't move right when repeat character
  --           :with_move(cond.none())
  --           -- don't delete if the next character is xx
  --           :with_del(cond.not_after_regex "xx")
  --           -- disable adding a newline when you press <cr>
  --           :with_cr(cond.none()),
  --       },
  --       -- disable for .vim files, but it work for another filetypes
  --       Rule("a", "a", "-vim")
  --     )
  --   end,
  -- },
  -- By adding to the which-key config and using our helper function you can add more which-key registered bindings
  -- {
  --   "folke/which-key.nvim",
  --   config = function(plugin, opts)
  --     require "plugins.configs.which-key"(plugin, opts) -- include the default astronvim config that calls the setup call
  --     -- Add bindings which show up as group name
  --     local wk = require "which-key"
  --     wk.register({
  --       b = { name = "Buffer" },
  --     }, { mode = "n", prefix = "<leader>" })
  --   end,
  -- },
}
