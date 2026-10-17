-- Files the plugin decrypts on open; it skips any without a $ANSIBLE_VAULT header.
-- *.env covers vault-encrypted env files kept outside ansible/, e.g. iac/infra
local patterns = { "*/vault.yml", "*/vault.yaml", "*.env" }

return {
  {
    "apayu/nvim-ansible-vault",
    -- setup() registers a BufReadPost autocmd, so loading on BufReadPre of the
    -- same patterns is early enough for the first vault file opened
    event = vim.tbl_map(function(p) return "BufReadPre " .. p end, patterns),
    opts = {
      patterns = patterns,
      vault_password_files = { ".vault_pass", ".vault-pass", ".ansible-key", "ansible/.ansible-key" },
    },
    config = function(_, opts)
      local av = require "ansible-vault"
      av.setup(opts)

      -- The plugin re-encrypts under vault id "default" and forces filetype=yaml.
      -- Keep the file's own id ($ANSIBLE_VAULT;1.2;AES256;<id>) so a save doesn't
      -- rewrite the header, and re-detect the filetype so .env stays .env
      local open = av.open_with_vault
      av.open_with_vault = function(file_path, identities)
        local header = vim.fn.readfile(file_path, "", 1)[1] or ""
        local id = header:match "^%$ANSIBLE_VAULT;1%.2;[^;]+;(.+)$"
        if id then
          identities = vim.tbl_map(function(i) return vim.tbl_extend("force", i, { name = id }) end, identities)
        end
        open(file_path, identities)
        vim.bo.filetype = vim.filetype.match { filename = file_path } or vim.bo.filetype
      end
    end,
  },
}
