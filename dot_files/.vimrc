set autoindent
set autoread
set shiftwidth=4
set tabstop=4
set smarttab
set ruler
set encoding=utf-8

set number
set relativenumber
set history=10000
set noswapfile

" Autoclose brakets
inoremap {<CR> {<CR>}<Esc>ko<tab>
inoremap [<CR> [<CR>]<Esc>ko<tab>
inoremap (<CR> (<CR>)<Esc>ko<tab>

if filereadable(expand("~/.vimrc.plug"))
	source ~/.vimrc.plug
endif
