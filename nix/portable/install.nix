{ lib, pkgs, sys, nixunits }:

pkgs.writeShellApplication {
  name = "nixunits-install";

  runtimeInputs = [ pkgs.systemd pkgs.coreutils pkgs.findutils ];

  text = let
    serviceUnit = sys.build.units."nixunits@.service".unit;
  in ''
    set -euo pipefail

    mkdir -p /var/lib/nixunits/store/default/root /var/lib/nixunits/containers /var/lib/nixunits/etc/systemd

    mkdir -p /usr/local/bin
    ln -sfn "${nixunits}/bin/nixunits" /usr/local/bin/nixunits
    ln -sfn "${serviceUnit}/nixunits@.service" /etc/systemd/system/nixunits@.service

    systemctl daemon-reload

    echo "[nixunits] Done"
  '';
}
