{
  config,
  pkgs,
  inputs,
  ...
}:

let
  ageKeyFile = "/persist/sops/fumosops.key";
  pgpFingerprint = "5F3C25D755D3A4321D03FF7135FAC098F119E8FA";
in
{
  imports = [
    inputs.sops-nix.homeManagerModules.sops
  ];

  sops = {
    age.keyFile = ageKeyFile;
    defaultSopsFile = ../secrets/secrets.yaml;
    validateSopsFiles = false;

    secrets = {
      "fumossh.key" = {
        path = "${config.home.homeDirectory}/.ssh/fumossh.key";
        mode = "0600";
      };
      "fumopgp.key" = {
        mode = "0600";
      };
      abacusai_api_key = {
        mode = "0600";
      };
    };

    templates."shell-secrets.sh".content = ''
      export ABACUSAI_API_KEY="${config.sops.placeholder.abacusai_api_key}"
    '';
  };

  systemd.user.services.sops-nix = {
    Unit.ConditionPathExists = ageKeyFile;
  };

  # Import SOPS-decrypted PGP signing key after decryption (including live secret
  # rotations) rather than forking `gpg -K` on every interactive shell prompt.
  systemd.user.services.sops-import-pgp = {
    Unit = {
      Description = "Import SOPS-managed PGP key into GnuPG keyring";
      Wants = [ "sops-nix.service" ];
      After = [ "sops-nix.service" ];
      ConditionPathExists = config.sops.secrets."fumopgp.key".path;
    };
    Install.WantedBy = [ "sops-nix.service" ];
    Service = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "sops-import-pgp" ''
        set -euo pipefail
        ${pkgs.gnupg}/bin/gpg --batch --import "${config.sops.secrets."fumopgp.key".path}"
        echo "${pgpFingerprint}:6:" | ${pkgs.gnupg}/bin/gpg --batch --import-ownertrust
      '';
    };
  };

  home.sessionVariables.SOPS_AGE_KEY_FILE = ageKeyFile;

  home.packages = with pkgs; [
    sops
    age
    ssh-to-age
  ];
}
