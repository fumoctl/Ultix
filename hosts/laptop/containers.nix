# Host-specific containers for fumonix-laptop.
# Merged with the shared set defined in ../containers.nix.
{ ... }:

{
  virtualisation.oci-containers.containers = {
    # Example:
    # some-service = {
    #   image = "docker.io/library/whatever:latest";
    #   autoStart = true;
    #   podman.user = "fumoctl";
    #   ports = [ "8080:8080" ];
    # };
  };
}
