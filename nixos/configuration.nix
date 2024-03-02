# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

# https://github.com/HeinzDev/Hyprland-dotfiles
{  pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ./programs.nix
      ./networking.nix
    ];

  # Boot settings
  boot = {
    tmp.cleanOnBoot = true;
    # Bootloader.
    loader ={
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  # Set your time zone.
  time.timeZone = "Europe/Moscow";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };


  # Configure keymap in X11
  # services.xserver = {
  #  layout = "us";
  #  xkbVariant = "";
  # };

  # Set fish as default shell for all users
  programs.fish.enable = true;
  users.defaultUserShell = pkgs.fish;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.x = {
    isNormalUser = true;
    useDefaultShell = true;
    shell = pkgs.fish;
    description = "X";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
    ];

    # packages = with pkgs; [];

    # Set user ssh keys
    #openssh.authorizedKeys.keys = [
    #  "ssh key"
    #];
  };


  # Graphics settings
  services.xserver = {
      enable = true;
      # videosDrivers = ["nvidia"];
      # videosDrivers = ["nouveau"];
      displayManager.gdm = {
          enable = true;
          wayland = true;
      };
  };

  # Enable Pipwire
  # Remove sound.enable or set it to false if you had it set previously, as sound.enable is only meant for ALSA-based configurations
  sound.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Hardware config
  hardware = {
    # OpenGL
    opengl = {
      enable = true;
      # Vulan enable attempt
      driSupport = true;
      driSupport32Bit = true;
      extraPackages = with pkgs; [
        vulkan-tools
        vulkan-loader
        vulkan-validation-layers
        vulkan-extension-layer
      ];
    };
  };

  #Garbage colector
  # nix.gc = {
  #   automatic = true;
  #   dates = "weekly";
  #   options = "--delete-older-than 30d";
  # };


  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = false;

  # Upgrade options
  system.autoUpgrade.enable = true;
  system.autoUpgrade.allowReboot = true;
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}

