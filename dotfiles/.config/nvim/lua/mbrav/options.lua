-- Key mappings conf

local options = {
  autoindent = true,
  smartindent = true,
  tabstop = 2,
  shiftwidth = 2,
  expandtab = true,
  showtabline = 0,
  showmatch = true,

  number = true,
  relativenumber = true,
  -- numberwidth = 2,
  incsearch = true,
  hlsearch = false,
  ignorecase = true,
  smartcase = true,

  splitbelow = true,
  splitright = true,

  termguicolors = true,
  hidden = true,
  signcolumn = "yes",
  showmode = false,
  errorbells = false,
  wrap = false,
  cursorline = false,
  fileencoding = "utf-8",

  backup = false,
  writebackup = false,
  swapfile = false,
  undodir = os.getenv "HOME" .. "/.vim/undodir",
  undofile = true,

  -- Always have more than 8 characters above and below
  scrolloff = 8,
  scrollback = 8,
  updatetime = 20,
  mouse = "a",
  guicursor = "a:block",

  title = true,
  -- titlestring = "%t - Wvim",
  titlestring = "Neovim - %t",
  -- guifont = "MesloLGS NF:h18",
  -- clipboard = "unnamedplus",
}

-- vim.opt.nrformats:append("alpha") -- increment letters
vim.opt.shortmess:append "IsF"

vim.g.vscode = true

for option, value in pairs(options) do
  vim.opt[option] = value
end
