{lib, pkgs}: with lib;
let
  moduleName = "nixunits";
  fileConf = name: "${pathContainers}/${name}/unit.conf";
  fileLock = name: "${pathContainers}/${name}/nixos.lock";
  fileNix = name: "${pathContainers}/${name}/unit.nix";
  fileCustom = name: "${pathCustoms}/${name}.nix";
  fileService = name: "${pathServices}/${name}.nix";
  pathRoot = name: "${pathContainers}/${name}/root";
  pathContainers = "${pathVar}/containers";
  pathCustoms = "${pathVar}/customs";
  pathServices = "${pathVar}/services";
  pathVar = "/var/lib/${moduleName}";

  assertions = {cfg, name}: [
    {
      assertion = cfg.network.hostIp4 == "" || cfg.network.ip4 != ""
        -> cfg.network.hostIp6 == "" || cfg.network.ip6 != "";
      message = ''IP missing with private veth enabled'';
    }
    {
      assertion = cfg.network.interface == "" || !isNetPriv cfg;
      message = ''Interface set with private veth enabled'';
    }
    {
      assertion = !strings.hasInfix "_" name;
      message = ''
        Names containing underscores are not allowed. Please rename the container '${name}'
      '';
    }
  ];

  cfgUnit = name: cfg: security.cfgValid cfg;

  configExtra = {config, ...}: {
    boot = {
      isContainer = true;
      postBootCommands = ''
        ${pkgs.libcap}/bin/capsh --print
      '';
    };
    # networking.hostName = mkDefault name;
    networking.useDHCP = false;
    nixpkgs.pkgs = pkgs;
    services.nscd.enable = false;
    system = {
      activationScripts.specialfs = mkForce "";
      nssModules = mkForce [];
      stateVersion = lib.mkDefault config.system.nixos.release;
    };
    systemd = {
      coredump.enable = false;
      oomd.enable = false;
      package = pkgs.systemdMinimal;
      suppressedSystemUnits = [
        "console-getty.service"
        "dbus-org.freedesktop.login1.service"
        "logrotate-checkconf.service"
        "run-initramfs.mount"
        "run-wrappers.mount"
        "systemd-bootctl@.service"
        "systemd-bootctl.socket"
        "systemd-hibernate-clear.service"
        "systemd-logind.service"
        "systemd-tmpfiles-setup.service"
        "suid-sgid-wrappers.service"
        "systemd-user-sessions.service"
      ];
    };
  };

  _conf_unit = name: cfg: {
    name = "${moduleName}/${name}.conf";
    value = {
      text = ''
        EXTRA_NSPAWN_FLAGS="${
          optionalString (cfg.extraFlags != [])
            (concatStringsSep " " cfg.extraFlags)
          + optionalString (isNetPriv cfg)
            " --private-network"
          + optionalString (isNetVEth cfg)
            " --network-veth"
          + optionalString (cfg.network.interface != "")
            " --network-interface=${cfg.network.interface}"}"
        HOST_IP4=${cfg.network.hostIp4}
        HOST_IP6=${cfg.network.hostIp6}
        IP4=${cfg.network.ip4}
        IP4ROUTE=${cfg.network.ip4route}
        IP6=${cfg.network.ip6}
        IP6ROUTE=${cfg.network.ip6route}
        INTERFACE=${cfg.network.interface}
        NAME=${name}
        SYSTEM_PATH=${cfg.config.system.build.toplevel}
      '';
    };
  };

  conf = cfg: {
    environment.etc = mapAttrs' _conf_unit cfg;
  };

  isNetVEth = cfg: cfg.network.hostIp4 != "" || cfg.network.hostIp6 != "";
  isNetPriv = cfg: (cfg.network.ip4 == "" && cfg.network.ip6 == "") || (isNetVEth cfg);

  security = import ./security.nix {inherit lib;};

in with lib; {
  inherit conf
    fileConf fileCustom fileLock fileNix fileService
    moduleName
    pathContainers pathCustoms pathRoot pathServices pathVar;
  options = {
    nixunits = mkOption {
      type = types.attrsOf (types.submodule (
        { config, options, name, ... }: {
          config = {
            extraFlags = (security.flags config.caps_allow) ++ [
              "--link-journal=host"
              "--bind-ro=/nix/store"
            ];
            # path = config.config.system.build.toplevel;
          };
          options = {
            autoStart = mkOption {
              default = false;
              description = ''
                Whether the container is automatically started at boot-time.
              '';
              type = types.bool;
            };

            boot.isContainer = mkOption {
              type = types.bool;
              default = true;
            };

            caps_allow = mkOption {
              default = [];
              type = types.listOf types.str;
            };

            config = mkOption {
              description = ''
                A specification of the desired configuration of this
                container, as a NixOS module.
              '';
              type = mkOptionType {
                name = "Toplevel NixOS config";
                merge = loc: defs: (import "${toString config.nixpkgs}/nixos/lib/eval-config.nix" {
                  inherit (config) specialArgs;
                  modules = [
                    configExtra
                    { config.assertions = (assertions {inherit name;cfg=config;}); }
                  ] ++ (map (x: cfgUnit name x.value) defs);
                  prefix = [ moduleName name ];

                  # The system is inherited from the host above.
                  # Set it to null, to remove the "legacy" entrypoint's non-hermetic default.
                  system = null;
                }).config;
              };
            };

            extraFlags = mkOption {
              default = [];
              description = ''
                Extra flags passed to the systemd-nspawn command.
                See systemd-nspawn(1) for details.
              '';
              example = [ "--drop-capability=CAP_SYS_CHROOT" ];
              type = types.listOf types.str;
            };

            network = mkOption {
              default = {};
              type = with types; submodule {
                options = {
                  hostIp4 = mkOption {
                    default = "";
                    type = str;
                  };
                  hostIp6 = mkOption {
                    default = "";
                    type = str;
                  };
                  interface = mkOption {
                    default = "";
                    type = str;
                  };
                  ip4 = mkOption {
                    default = "";
                    type = str;
                  };
                  ip6 = mkOption {
                    default = "";
                    type = str;
                  };
                  ip4route = mkOption {
                    default = "";
                    type = str;
                  };
                  ip6route = mkOption {
                    default = "";
                    type = str;
                  };
                };
              };
            };

            nixpkgs = mkOption {
              default = pkgs.path;
              defaultText = literalExpression "pkgs.path";
              description = ''
                A path to the nixpkgs that provide the modules, pkgs and lib for evaluating the container.

                To only change the `pkgs` argument used inside the container modules,
                set the `nixpkgs.*` options in the container {option}`config`.
                Setting `config.nixpkgs.pkgs = pkgs` speeds up the container evaluation
                by reusing the system pkgs, but the `nixpkgs.config` option in the
                container config is ignored in this case.
              '';
              type = types.path;
            };

            specialArgs = mkOption {
              default = {};
              description = ''
                A set of special arguments to be passed to NixOS modules.
                This will be merged into the `specialArgs` used to evaluate
                the NixOS configurations.
              '';
              type = types.attrsOf types.unspecified;
            };
          };
        }));

      default = {};
      description = ''
        A set of NixOS system configurations to be run as lightweight containers.
        Each container appears as a service `nixunits@«name»`
        on the host system, allowing it to be started and stopped via
        {command}`systemctl`.
      '';
    };
  };
}
