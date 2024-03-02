# Programs configuration
{ pkgs, ... }:
{
  # Enable Sway with Wayland compositor
  # programs.sway.enable = true;

  # Enable Hyperland with Wayland compositor
  programs.hyprland = {
    # Install the packages from nixpkgs
    enable = true;
    # Whether to enable XWayland
    xwayland.enable = true;

    # Optional
    # Whether to enable patching wlroots for better Nvidia support
    # enableNvidiaPatches = true;
  };

  environment.sessionVariables = {
    # If your cursor becomes invisible
    WLR_NO_HARDWARE_CURSORS = "1";
    # Hint electron apps to use wayland
    NIXOS_OZONE_WL = "1";
  };

  # XDG portal
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  # File browser
  programs.thunar.enable = true;
  # Mount, trash, and other functionalities
  services.gvfs.enable = true;
  # Thumbnail support for images
  services.tumbler.enable = true;
  # Thunar plugins
  programs.thunar.plugins = with pkgs.xfce; [
    thunar-archive-plugin
    thunar-volman
    thunar-media-tags-plugin
  ];

  # gnupg config 
  services.pcscd.enable = true;
  programs.gnupg.agent = {
     enable = true;
     pinentryFlavor = "curses";
     enableSSHSupport = true;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
     fish
     vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
     neovim
     tmux
     htop
     neofetch
     starship
     fzf
     mcfly
     eza
     wget
     unzip
     # gnupg
     fd
     # Fish plugins
     # fishPlugins.done
     # fishPlugins.fzf-fish
     # fishPlugins.forgit
     # fishPlugins.hydro
     # fishPlugins.grc
     grc
     # Terminal
     alacritty
     kitty
     # Dev
     git
     nodejs
     docker
     lazygit
     #gcc
     clang
     rustup
     python3
     # Nix
     nixpkgs-lint
     nixpkgs-fmt
     nixfmt
     # Dictionary
     aspell
     aspellDicts.en
     aspellDicts.ru
     aspellDicts.en-computers
     hunspell
     hunspellDicts.en-us
     hunspellDicts.ru-ru
     # Wayland stuff
     waybar # Nav Bar
     eww # Nav Bar customization with widgets
     swww # Background manager
     dunst # Notifications
     libnotify # Notification dependency
     networkmanagerapplet # Applet for managing network settings
     rofi-wayland # App selector
     wl-clipboard # wl-copy and wl-paste for copy/paste from stdin / stdout

     nerdfonts
     # Desktop Programs
     firefox
     mpv
     feh # Image viewer
  ];

  # Fonts
  fonts = {
    fontDir.enable = true;
    packages = with pkgs; [
      twitter-color-emoji
      # fira-code
      # fira
      jetbrains-mono
      # iosevka
      # bitmap
      # spleen
      # fira-code-symbols
      powerline-fonts
      (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
    ];
  };
}
