{
  config,
  lib,
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    # Default Konsole profile discovered via XDG_DATA_DIRS (keeps ~/.local/share/konsole
    # writable for Noctalia's `konsole` colorscheme template and GUI profile edits).
    (writeTextDir "share/konsole/Ultix.profile" ''
      [Appearance]
      ColorScheme=noctalia
      Font=Inconsolata Nerd Font,14,-1,5,700,0,0,0,1,0,0,0,0,0,0,1,Bold

      [General]
      Name=Ultix
      Parent=FALLBACK/
    '')
    btop
    eza
    bat
    fzf
  ];

  # Fastfetch configuration & randomized PNG logos (~/.config/fastfetch)
  xdg.configFile."fastfetch".source = ../dotfiles/fastfetch;

  # SSH client configuration with non-symlink 0600 permission safety.
  # Only github.com sets IdentitiesOnly; Host * leaves SSH_AUTH_SOCK (gpg-agent) usable.
  home.activation.sshConfig =
    let
      sshConfig = pkgs.writeText "ssh-config" ''
        Host github.com
            HostName github.com
            User git
            IdentityFile ~/.ssh/fumossh.key
            IdentitiesOnly yes

        Host *
            IdentityFile ~/.ssh/id_ed25519
      '';
    in
    lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
      mkdir -p -m 700 ~/.ssh && rm -f ~/.ssh/config_source && install -m 600 ${sshConfig} ~/.ssh/config
    '';

  # Git with commit signing
  programs.git = {
    enable = true;
    signing = {
      key = "35FAC098F119E8FA";
      signByDefault = true;
    };
    settings = {
      user = {
        name = "JuanU";
        email = "juanu@fumoctl.com";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

  programs.zsh = {
    enable = true;
    history.path = "${config.xdg.stateHome}/zsh/history";
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initContent = ''
      [ -f "${config.sops.templates."shell-secrets.sh".path}" ] && source "${
        config.sops.templates."shell-secrets.sh".path
      }"
    '';
    oh-my-zsh = {
      enable = true;
      theme = "dpoggi";
      plugins = [
        "git"
        "sudo"
      ];
    };
  };

  home.activation.migrateZshHistory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    hist="''${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
    if [ ! -s "$hist" ]; then
      for old in "$HOME/.config/zsh/.zsh_history" "/persist$HOME/.config/zsh/.zsh_history"; do
        if [ -s "$old" ]; then
          install -Dm600 "$old" "$hist"
          break
        fi
      done
    fi
  '';
}
