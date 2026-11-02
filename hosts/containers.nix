{
  pkgs,
  ...
}:

{
  environment.systemPackages = with pkgs; [
    # --- Container Orchestration & CLI ---
    docker-compose # Official Compose v2 plugin/binary for rootful Docker
    podman-compose # Compose parser for Podman
    podman-desktop

    # --- Local Kubernetes & Workloads ---
    kind # Kubernetes IN Docker/Podman
    kubectl # K8s CLI
    helm # K8s package manager
    k9s # Fast terminal UI for interacting with your K8s clusters

    # --- Image Inspection & Registries ---
    skopeo # Inspect, copy, and sign container images without pulling/running them
    dive # Inspect layer-by-layer contents and sizes of container images

    # --- Rootless / CNI Utilities ---
    shadow # Provides subuid/subgid helpers (newuidmap, newgidmap)
    fuse-overlayfs # Fallback userspace storage driver for unprivileged containers
  ];

  programs.virt-manager.enable = true;
  services.spice-vdagentd.enable = true;

  virtualisation = {
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
        vhostUserPackages = with pkgs; [
          virtiofsd
        ];
      };
    };

    docker = {
      enable = true;
      autoPrune.enable = true;
    };

    podman = {
      enable = true;

      # CRITICAL: Do NOT enable dockerCompat or dockerSocket.enable
      dockerCompat = false; # Leaves the `docker` CLI pointing to dockerd
      dockerSocket.enable = false; # Leaves /var/run/docker.sock to Docker

      # Enable Netavark/DNS support for Podman internal container resolution
      defaultNetwork.settings.dns_enabled = true;
    };

    containers.storage.settings = {
      storage = {
        driver = "overlay";
      };
    };

    oci-containers = {
      backend = "podman";

      # Shared containers available on every host. Host-specific containers
      # live in hosts/<host>/containers.nix and are merged with these.
      containers = {
        yugabyte = {
          image = "docker.io/yugabytedb/yugabyte:latest";
          autoStart = false;
          podman.user = "fumoctl";
          cmd = [
            "bin/yugabyted"
            "start"
            "--daemon=false"
            "--advertise_address=127.0.0.1"
          ];
          extraOptions = [ "--network=host" ];
          volumes = [
            "yugabyte-data:/home/yugabyte/var:Z"
          ];
        };
      };
    };
  };
}
