{
  lib,
  pkgs,
  ...
}:

let
  # Extend Podman's default seccomp allowlist with the three io_uring syscalls
  # so PostgreSQL 18+ can use native Linux `io_method = io_uring` without
  # dropping container syscall sandboxing (`seccomp=unconfined`).
  postgresSeccomp =
    pkgs.runCommand "postgres-io-uring-seccomp.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq '.syscalls += [{
          names: ["io_uring_setup", "io_uring_enter", "io_uring_register"],
          action: "SCMP_ACT_ALLOW",
          args: [],
          comment: "Allow PostgreSQL 18+ native io_uring AIO",
          includes: {},
          excludes: {}
        }]' "${pkgs.podman.src}/vendor/go.podman.io/common/pkg/seccomp/seccomp.json" > "$out"
      '';
in
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
        postgres = {
          image = "docker.io/library/postgres:18";
          autoStart = true;
          podman.user = "fumoctl";
          environment = {
            POSTGRES_USER = "postgres";
            POSTGRES_DB = "postgres";
            POSTGRES_HOST_AUTH_METHOD = "trust";
          };
          volumes = [
            "postgres-data:/var/lib/postgresql:Z"
          ];
          extraOptions = [
            "--network=host"
            "--shm-size=1g"
            "--stop-timeout=60"
            "--security-opt=seccomp=${postgresSeccomp}"
          ];
          cmd = [
            "postgres"
            # Network: bind strictly to loopback (pairs with --network=host)
            "-c"
            "listen_addresses=127.0.0.1,::1"
            "-c"
            "port=5432"
            "-c"
            "max_connections=100"

            # Memory: fast hot cache with bounded background RAM footprint
            "-c"
            "shared_buffers=512MB"
            "-c"
            "effective_cache_size=4GB"
            "-c"
            "work_mem=16MB"
            "-c"
            "maintenance_work_mem=256MB"
            "-c"
            "huge_pages=try"

            # PostgreSQL 18 Linux-native async I/O & NVMe planner cost model
            "-c"
            "io_method=io_uring"
            "-c"
            "effective_io_concurrency=200"
            "-c"
            "maintenance_io_concurrency=200"
            "-c"
            "random_page_cost=1.1"

            # Btrfs CoW-friendly WAL & low-wakeup checkpoints (crash-safe: fsync=on)
            "-c"
            "synchronous_commit=off"
            "-c"
            "wal_compression=lz4"
            "-c"
            "wal_buffers=16MB"
            "-c"
            "wal_init_zero=off"
            "-c"
            "wal_recycle=off"
            "-c"
            "checkpoint_timeout=30min"
            "-c"
            "checkpoint_completion_target=0.9"
            "-c"
            "max_wal_size=2GB"
            "-c"
            "min_wal_size=128MB"

            # Parallelism & quiet idle housekeeping
            "-c"
            "max_worker_processes=8"
            "-c"
            "max_parallel_workers=4"
            "-c"
            "max_parallel_workers_per_gather=2"
            "-c"
            "max_parallel_maintenance_workers=2"
            "-c"
            "jit=off"
            "-c"
            "bgwriter_delay=500ms"
            "-c"
            "autovacuum_naptime=5min"
          ];
        };
      };
    };
  };

  # Ensure rootless runtime/storage mounts exist before boot autostart, and
  # deprioritize CPU/IO contention + bound cgroup RAM so background Postgres
  # never impacts desktop responsiveness or gaming frame pacing.
  systemd.services.podman-postgres = {
    after = [ "user@1000.service" ];
    requires = [ "user@1000.service" ];
    unitConfig.RequiresMountsFor = lib.mkForce "/run/user/1000/containers /home/fumoctl/.local/share/containers";
    serviceConfig = {
      LimitMEMLOCK = "infinity";
      Nice = 5;
      CPUWeight = 50;
      IOWeight = 50;
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 6;
      MemoryHigh = "2G";
      MemoryMax = "3G";
    };
  };
}
