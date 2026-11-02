{
  config,
  pkgs,
  inputs,
  ...
}:

let
  ageKeyFile = "/persist/sops/fumosops.key";
  pgpKeyId = "35FAC098F119E8FA";
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

  # Import SOPS-decrypted PGP signing key once after decryption rather than
  # forking `gpg -K` on every interactive shell prompt.
  systemd.user.services.sops-import-pgp = {
    Unit = {
      Description = "Import SOPS-managed PGP key into GnuPG keyring";
      After = [ "sops-nix.service" ];
      ConditionPathExists = config.sops.secrets."fumopgp.key".path;
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "sops-import-pgp" ''
        if ! ${pkgs.gnupg}/bin/gpg -K ${pgpKeyId} >/dev/null 2>&1; then
          ${pkgs.gnupg}/bin/gpg --batch --import "${config.sops.secrets."fumopgp.key".path}" >/dev/null 2>&1
          echo "${pgpFingerprint}:6:" | ${pkgs.gnupg}/bin/gpg --batch --import-ownertrust >/dev/null 2>&1
        fi
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
