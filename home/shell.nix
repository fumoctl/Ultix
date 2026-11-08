{
  config,
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

  # SSH client configuration with non-symlink 0600 permission safety
  home.file.".ssh/config_source" = {
    text = ''
      Host github.com
          HostName github.com
          User git
          IdentityFile ~/.ssh/fumossh.key

      Host *
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
    '';
    onChange = ''
      install -m 600 ~/.ssh/config_source ~/.ssh/config
    '';
  };

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
}
