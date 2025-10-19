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

    install -Dm755 "${nixunits}/bin/nixunits" /usr/local/bin/nixunits
    cp -r "${nixunits}/bin" "${nixunits}/services" "${nixunits}/tests" "${nixunits}/unit" /usr/local/lib/nixunits/

    install -Dm644 ${nixunits}/unit/* /etc/systemd/system/
    systemctl daemon-reload

    echo "[nixunits] ✅ Done"
  '';
}
