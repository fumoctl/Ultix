{
  inputs,
  ...
}:

{
  imports = [ inputs.windscribe-nixos.nixosModules.windscribe ];

  networking = {
    nftables.enable = true;

    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
      settings = {
        main = {
          dns = "systemd-resolved";
        };
        connection = {
          "ipv4.ignore-auto-dns" = true;
          "ipv6.ignore-auto-dns" = true;
          "wifi.cloned-mac-address" = "stable-temporary";
          "ethernet.cloned-mac-address" = "stable-temporary";
          "ipv6.ip6-privacy" = 2;
        };
        device = {
          "wifi.scan-rand-mac-address" = "yes";
        };
      };
    };

    firewall = {
      enable = true;
      checkReversePath = "loose";
      trustedInterfaces = [
        "tun0"
        "tun2"
        "amn0"
        "utun420"
      ];
    };
  };

  services.unbound.enable = false;

  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        DNSSEC = "true";
        DNSOverTLS = "true";
        DNS = [
          "94.140.14.14#dns.adguard-dns.com"
          "94.140.15.15#dns.adguard-dns.com"
          "2a10:50c0::ad1:ff#dns.adguard-dns.com"
          "2a10:50c0::ad2:ff#dns.adguard-dns.com"
        ];
        FallbackDNS = [
          "9.9.9.9#dns.quad9.net"
          "149.112.112.112#dns.quad9.net"
          "2620:fe::fe#dns.quad9.net"
          "2620:fe::9#dns.quad9.net"
          "194.242.2.4#base.dns.mullvad.net"
          "2a07:e340::4#base.dns.mullvad.net"
        ];
        Domains = [ "~." ];
      };
    };
  };

  programs.windscribe = {
    enable = true;
    users = [ "fumoctl" ];
  };
}
