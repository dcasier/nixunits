{ lib, pkgs, global, nixunits}:

with lib;

let
  autoStartFilter = cfg: filterAttrs (n: v: v.autoStart or false) cfg;
  moduleName = global.moduleName;

  serviceConfig = {
    # ExecReload = TODO
    Delegate = true;
    Environment="SYSTEMD_NSPAWN_UNIFIED_HIERARCHY=1";
    ExecStart="systemd-nspawn --machine=%i -D ${global.pathRoot "%i"} --notify-ready=yes --kill-signal=SIGRTMIN+3 $NSPAWN_ARGS \${SYSTEM_PATH}/init";
    ExecStartPre="${nixunits}/unit/nixunit-start-pre";
    ExecStartPost="${nixunits}/unit/nixunit-start-post";
    EnvironmentFile = "${global.unitConf "%i"}";
    KillMode = "mixed";
    Restart = "on-failure";
    # Note that on reboot, systemd-nspawn returns 133, so this
    # unit will be restarted. On poweroff, it returns 0, so the
    # unit won't be restarted.
    RestartForceExitStatus = "133";
    Slice = "machine.slice";
    SuccessExitStatus = "133";
    SyslogIdentifier = "nixunit %i";
    TasksMax = "16384";
    TimeoutStartSec = "1min";
    Type = "notify";
  };

#  startPost = pkgs.runCommand scriptStartPost { } ''
#    install -D ${./src/unit/${scriptStartPost}} $out/bin/${scriptStartPost}
#    chmod +x $out/bin/${scriptStartPost}
#  '';

  unit = {
    description = "NixUnit container '%i'";
    unitConfig.RequiresMountsFor = "${global.pathContainers}/%i";
    path = [ pkgs.iproute2 ];
    restartIfChanged = false;
    inherit serviceConfig;
  };

in {
  systemd = {
    services = listToAttrs (filter (x: x.value != null) (
      [{
        name = "${moduleName}@";
        value = unit // {
          aliases = mapAttrsToList (
            name: cfg: "${moduleName}@${name}.service"
          ) (autoStartFilter config.${moduleName});
        };
      }]
      ++ (mapAttrsToList (name: cfg: nameValuePair "${moduleName}@${name}" (
          { wantedBy = [ "${moduleName}.target" ]; }
          )
      ) (autoStartFilter config.${moduleName}))
    ));

    targets.multi-user.wants = [ "machines.target" ];

    tmpfiles.rules = [
     "d ${global.pathContainers} 2770 root ${moduleName}"
     "d ${global.pathVar} 2770 root ${moduleName}"
    ]
    ++ concatMap (name: [
      "d ${global.pathRoot name} 0755 root root - -"
      "L+ ${global.unitConf name} - - - - /etc/${moduleName}/${name}.conf"
    ]) (attrNames config.${moduleName});
  };

  users.groups.nixunits = {};
}
