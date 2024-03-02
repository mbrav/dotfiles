# Networking module

{ ... }:
{
  networking = {
    hostName = "nixos";
    wireless.enable = false;
    networkmanager.enable = true;
    enableIPv6 = false;

    # Configure network proxy if necessary
    # proxy = {
    #   default = "http://user:password@proxy:port/";
    #   noProxy = "127.0.0.1,localhost,internal.domain";
    # };

    # Open ports in the firewall.
    # firewall.allowedTCPPorts = [ ... ];
    # firewall.allowedUDPPorts = [ ... ];
    # Or disable the firewall altogether.
    firewall.enable = false;
  };
}

