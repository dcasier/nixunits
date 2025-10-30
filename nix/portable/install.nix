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

    mkdir -p /var/lib/nixunits/store/default/root /var/lib/nixunits/containers /var/lib/nixunits/etc/systemd
    cat >/var/lib/nixunits/etc/systemd/nixunits@.service <<EOF
    [Install]
    WantedBy=machines.target

    [Unit]
    Description=NixUnit container '%i'
    RequiresMountsFor=/var/lib/nixunits/containers/%i
    Wants=network-online.target
    After=network-online.target

    [Service]
    Environment=SYSTEMD_NSPAWN_UNIFIED_HIERARCHY=1
    EnvironmentFile=/var/lib/nixunits/containers/%i/unit.conf

    ExecStartPre=${nixunits}/unit/nixunit-start-pre
    ExecStart=${nixunits}/unit/nixunit-start
    ExecStop=${nixunits}/unit/nixunit-stop-pre
    ExecStop=/usr/bin/machinectl terminate %i
    ExecStopPost=/usr/bin/machinectl wait %i || true

    Delegate=true
    KillMode=mixed
    Restart=on-failure
    RestartForceExitStatus=133
    Slice=machine.slice
    SuccessExitStatus=133
    SyslogIdentifier=nixunit %i
    TasksMax=16384
    TimeoutStartSec=1min
    Type=notify
    EOF

    mkdir -p /usr/local/bin
    ln -sfn "${nixunits}/bin/nixunits" /usr/local/bin/nixunits
    ln -sfn "/var/lib/nixunits/etc/systemd/nixunits@.service" /etc/systemd/system/nixunits@.service

    systemctl daemon-reload

    echo "[nixunits] Done"
  '';
}
