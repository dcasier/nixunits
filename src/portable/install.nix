{ lib, pkgs, global, nixunits }:

pkgs.writeShellApplication {
  name = "nixunits-install";

  runtimeInputs = [ pkgs.systemd pkgs.coreutils pkgs.findutils ];

  text = ''
    set -euo pipefail

    for cmd in machinectl systemd-nspawn; do
      if ! command -v $cmd >/dev/null 2>&1; then
        echo "[nixunits] Error: missing dependency '$cmd'. Please install systemd-container."
        exit 1
      fi
    done

    mkdir -p /usr/local/lib/nixunits /var/lib/nixunits/containers

    rm -fr /usr/local/lib/nixunits/*
    cp -r ${nixunits}/* /usr/local/lib/nixunits/
    install -Dm755 "${nixunits}/bin/nixunits" /usr/local/bin/nixunits

    units=(
      "portable/nixunits@.service"
      "unit/nixunit-start-pre"
      "unit/nixunit-start-post"
    )

    for unit in "''${units[@]}"; do
        src="${nixunits}/''${unit}"
        dest="/etc/systemd/system/$(basename "$unit")"

        if [[ -L "$dest" ]] || [[ -L "$dest" ]]; then
          /bin/rm "$dest"
        fi
        ln -s "$src" "$dest"
    done
    systemctl daemon-reload

    echo "[nixunits] Done"
  '';
}
