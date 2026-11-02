{
  # Plain Vim stays a fallback editor beside Neovim: built-in options only, no plugins.
  xdg.configFile."vim/vimrc".text = ''
    " A user vimrc skips defaults.vim unless it is sourced explicitly.
    source $VIMRUNTIME/defaults.vim

    set background=dark
    set number
    set cursorline
    set laststatus=2
    set showmatch
    set hlsearch
    set ignorecase
    set smartcase
    set autoindent
    set expandtab
    set tabstop=4
    set shiftwidth=4
    set softtabstop=4
  '';

  # The vim package ships this entry, but no gvim binary exists.
  xdg.dataFile."applications/gvim.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=GVim
    Hidden=true
  '';
}
