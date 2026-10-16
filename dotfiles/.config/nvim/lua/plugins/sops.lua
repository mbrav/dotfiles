return {
  {
    "trixnz/sops.nvim",
    -- Not lazy: the plugin registers autocmds that must already be in place
    -- when an encrypted file is opened, otherwise the buffer loads as ciphertext
    lazy = false,
    opts = {
      disabled = false,
    },
  },
}
