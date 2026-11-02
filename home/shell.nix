{
  config,
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    ptyxis
    btop
    eza
    bat
    fzf
  ];

  # Terminal Emulator (Ptyxis) settings
  dconf.settings = {
    "org/gnome/Ptyxis" = {
      restore-session = false;
      use-system-font = false;
      font-name = "Inconsolata Nerd Font Mono Bold 14";
    };
  };

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
