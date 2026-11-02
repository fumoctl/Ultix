{
  imports = [
    ./secrets.nix
    ./noctalia.nix
    ./shell.nix
    ./apps.nix
    ./flatpak.nix
    ./mime.nix
  ];

  home.username = "fumoctl";
  home.homeDirectory = "/home/fumoctl";
  home.stateVersion = "26.05";

  # GNOME Keyring user service for the Hyprland session (wants
  # graphical-session-pre.target, wired up by UWSM).
  # Explicit components so the daemon does NOT spawn its own SSH agent —
  # programs.gnupg.agent (enableSSHSupport) owns SSH_AUTH_SOCK.
  services.gnome-keyring = {
    enable = true;
    components = [
      "pkcs11"
      "secrets"
    ];
  };
}
