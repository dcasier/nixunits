{ lib, pkgs, sys, nixunits }:

pkgs.writeShellApplication {
  name = "nixunits-install";

  runtimeInputs = [ pkgs.systemd pkgs.coreutils pkgs.findutils ];

  text = let
    # networkPath = sys.build.units."nixunits-network@.path".unit;
    networkUnit = sys.build.units."nixunits-network@.service".unit;
    serviceUnit = sys.build.units."nixunits@.service".unit;
  in ''
    set -euo pipefail

    mkdir -p /var/lib/nixunits/store/defaultroot /var/lib/nixunits/containers

    mkdir -p /usr/local/bin
    ln -sfn "${nixunits}/bin/nixunits" /usr/local/bin/nixunits
    ln -sfn "${networkUnit}/nixunits-network@.service" /etc/systemd/system/nixunits-network@.service
    ln -sfn "${serviceUnit}/nixunits@.service" /etc/systemd/system/nixunits@.service

    systemctl daemon-reload
    systemctl reset-failed

    echo "[nixunits] Done"
  '';
}
