{ config, global, lib, pkgs, nixunits }@host:

with lib;

let
  autoStartFilter = cfg:
    filterAttrs(n: v: v.autoStart) cfg;

  moduleName = global.moduleName;

  serviceConfig = {
    # ExecReload = TODO
    Delegate = true;
    Environment="SYSTEMD_NSPAWN_UNIFIED_HIERARCHY=1";
    ExecStartPre="${nixunits}/unit/nixunit-start-pre";
    ExecStart="systemd-nspawn --machine=%i -D ${global.pathRoot "%i"} --notify-ready=yes --kill-signal=SIGRTMIN+3 $NSPAWN_ARGS \${SYSTEM_PATH}/init";
    ExecStartPost="${nixunits}/unit/nixunit-start-post";
    ExecStop="${nixunits}/unit/nixunit-stop";
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
    TimeoutStartSec = "10min";
    Type = "notify";
  };

  unit = {
    description = "NixUnit container '%i'";
    path = [ pkgs.iproute2 ];
    restartIfChanged = false;
    unitConfig.RequiresMountsFor = "${global.pathContainers}/%i";
    wantedBy = [ "multi-user.target" ];
    inherit serviceConfig;
  };
in

{
    services = listToAttrs (filter (x: x.value != null) ([
      {
        name = "${moduleName}-network@";
        value = {
          after = [ "machine-%i.scope" ];
          bindsTo = [ "machine-%i.scope" ];
          description = "Configure network for machine %i";
          serviceConfig = {
            EnvironmentFile = "${global.unitConf "%i"}";
            ExecStart = "${nixunits}/unit/nixunit-network-config";
            Type = "oneshot";
          };
          wantedBy = [ "machine-%i.scope" ];
        };
      }
      {
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
}
