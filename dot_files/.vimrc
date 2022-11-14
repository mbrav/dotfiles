set autoindent
set shiftwidth=4
set tabstop=4
set smarttab

set encoding=utf-8

set number
set relativenumber
set history=1000
set noswapfile

if filereadable(expand("~/.vimrc.plug"))
	source ~/.vimrc.plug
endif
