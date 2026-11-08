{
  config,
  lib,
  pkgs,
  ...
}:

let
  associate = desktop: types: lib.genAttrs types (_: desktop);
in
{
  xdg.mimeApps = {
    enable = true;
    defaultApplications = lib.mergeAttrsList [
      # Web & Mail
      (associate "vivaldi-stable.desktop" [
        "text/html"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ])
      {
        "x-scheme-handler/mailto" = "thunderbird.desktop";
        "inode/directory" = "org.kde.dolphin.desktop";
        "application/pdf" = "org.kde.okular.desktop";
      }

      # Code, config & plaintext (VSCodium)
      (associate "codium.desktop" [
        "text/plain"
        "text/markdown"
        "text/x-markdown"
        "application/json"
        "application/x-yaml"
        "text/yaml"
        "text/x-yaml"
        "application/toml"
        "text/x-toml"
        "application/xml"
        "text/xml"
        "text/x-ini"
        "text/x-properties"
        "application/x-shellscript"
        "text/x-shellscript"
        "application/x-bash"
        "text/x-python"
        "application/x-python-code"
        "text/x-lua"
        "text/x-c"
        "text/x-csrc"
        "text/x-chdr"
        "text/x-c++"
        "text/x-c++src"
        "text/x-c++hdr"
        "text/x-rust"
        "text/rust"
        "text/x-go"
        "text/javascript"
        "application/javascript"
        "text/typescript"
        "application/typescript"
        "text/css"
        "text/x-scss"
        "text/x-sql"
        "text/x-diff"
        "text/x-patch"
        "text/x-dockerfile"
        "text/x-makefile"
        "text/x-cmake"
      ])

      # Photos & Images (Gwenview)
      (associate "org.kde.gwenview.desktop" [
        "image/jpeg"
        "image/png"
        "image/gif"
        "image/webp"
        "image/svg+xml"
        "image/bmp"
        "image/tiff"
        "image/avif"
        "image/heic"
        "image/x-icon"
      ])

      # Music & Audio (Elisa)
      (associate "org.kde.elisa.desktop" [
        "audio/mpeg"
        "audio/flac"
        "audio/x-vorbis+ogg"
        "audio/ogg"
        "audio/mp4"
        "audio/aac"
        "audio/x-wav"
      ])

      # Compressed Archives (Ark)
      (associate "org.kde.ark.desktop" [
        "application/zip"
        "application/x-tar"
        "application/x-compressed-tar"
        "application/x-bzip-compressed-tar"
        "application/x-bzip2-compressed-tar"
        "application/x-xz-compressed-tar"
        "application/x-zstd-compressed-tar"
        "application/x-7z-compressed"
        "application/vnd.rar"
        "application/x-rar"
        "application/gzip"
        "application/x-bzip2"
        "application/x-xz"
        "application/zstd"
      ])

      # Video Players (mpv)
      (associate "mpv.desktop" [
        "video/mp4"
        "video/mkv"
        "video/webm"
        "video/x-matroska"
        "video/quicktime"
        "video/x-msvideo"
      ])

      # Windows Executables (Bottles)
      (associate "com.usebottles.bottles.desktop" [
        "application/x-ms-dos-executable"
        "application/x-msdownload"
        "application/x-msi"
        "application/vnd.microsoft.portable-executable"
      ])
    ];
  };

  # Rebuild KDE's KSycoca desktop/MIME index on activation so Dolphin immediately
  # sees updated user/system .desktop files and MIME associations.
  home.activation.rebuildKdeSycoca = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rm -f "${config.xdg.cacheHome}/ksycoca"*
    XDG_CONFIG_DIRS="/etc/xdg:/etc/profiles/per-user/${config.home.username}/etc/xdg:/run/current-system/sw/etc/xdg" \
    XDG_DATA_DIRS="${config.xdg.dataHome}:/etc/profiles/per-user/${config.home.username}/share:/run/current-system/sw/share" \
    XDG_MENU_PREFIX="umbriel-" \
      ${pkgs.kdePackages.kservice}/bin/kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
  '';
}
