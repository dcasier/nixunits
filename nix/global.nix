{lib, pkgs, ...}: with lib;
let
  moduleName = "nixunits";
  unitConf = name: "${pathContainers}/${name}/unit.conf";
  pathRoot = name: "${pathContainers}/${name}/root";
  pathContainers = "${pathVar}/containers";
  pathVar = "/var/lib/${moduleName}";

  assertions = {cfg, name}: [
    {
      assertion = !strings.hasInfix "_" name;
      message = ''
        Names containing underscores are not allowed. Please rename container '${name}'
      '';
    }
  ];

  cfgUnit = name: cfg: security.cfgValid cfg;

  configExtra = {config, ...}: {
    boot = {
      isContainer = true;
      postBootCommands = ''
        ${pkgs.libcap}/bin/capsh --print
        ln -sf ${pkgs.bashInteractive}/bin/bash /bin/bash
      '';
    };
    environment = {
      systemPackages = with pkgs; [
        jq
      ];
    };
    # networking.hostName = mkDefault name;
    networking = {
      resolvconf.enable = false;
      useDHCP = false;
    };
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
#      paths."wait-net-ready" = {
#        after = [ "network-pre.target" ];
#        description = "Wait host signal";
#        pathConfig = {
#          PathExists = "/run/net-ready";
#        };
#        wantedBy = [ "network-pre.target" ];
#      };
      services."wait-net-ready" = {
        before = [ "network-pre.target" "network-online.target" ];
        wantedBy = [ "network-pre.target" "network-online.target" ];
        description = "Wait network ready";
        serviceConfig = let
          waitNetReady = pkgs.writeShellScript "wait-net-ready.sh" ''
            set -eu
            # while filepath=$(${pkgs.inotify-tools}/bin/inotifywait -e create --format '%w%f' /run); do
            while ! [ -f "/run/net-ready" ];do
                sleep 0.1
            done
            echo "###"
            echo "### Network ready"
            while ${pkgs.iproute2}/bin/ip -6 a| grep -q "tentative"; do
                sleep 0.5
            done
            ${pkgs.iproute2}/bin/ip a
            rm -f /run/net-ready
          '';
        in {
          ExecStart = "${waitNetReady}";
          Type = "oneshot";
        };
      };
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
        "systemd-nspawn.service"
        "systemd-nspawn@.service"
        # "systemd-tmpfiles-setup.service"
        "suid-sgid-wrappers.service"
        "systemd-user-sessions.service"
      ];
      targets.multi-user.requires = [ "basic.target" "wait-net-ready.service" ];
    };
  };

  _conf_unit = name: cfg: let
      interfaces = cfg.network.interfaces or {};

      isNetPriv = !(cfg ? network);
      isNetNS = cfg ? network && cfg.network ? netns_path && cfg.network.netns_path != "";

      isVeth = iface: iface.hostIp4 or "" != "" || iface.hostIp6 or "" != "";
      vethEnabled = builtins.any isVeth (builtins.attrValues interfaces);
      nonVethIfaces = (lib.filterAttrs (_: iface: !isVeth iface) interfaces);

      extraFile =
        if cfg.extra != ""
        then pkgs.writeText "${name}-extra.sh" cfg.extra
        else null;
      nftFile =
        if cfg.network ? nft && cfg.network.nft != ""
        then pkgs.writeText "${name}-ruleset.nft" cfg.network.nft
        else null;
      sysctlFile =
        if cfg ? sysctl && cfg.sysctl != ""
        then pkgs.writeText "${name}-sysctl" cfg.sysctl
        else null;
  in {
    name = "${moduleName}/${name}.conf";
    value = {
      text = ''
        NSPAWN_ARGS="${
          optionalString (cfg.nspawnArgs != [])
            (concatStringsSep " " cfg.nspawnArgs)
          + optionalString (isNetNS) " --network-namespace-path=${cfg.network.netns_path}"
          + optionalString (isNetPriv) " --private-network"
          + optionalString (vethEnabled) " --network-veth"
          + lib.concatStringsSep " " (
            lib.mapAttrsToList
              (name: _: " --network-interface=${name}")
              nonVethIfaces
          )
        } --overlay-ro=/var/lib/nixunits/store/default/root/nix/store/:/var/lib/nixunits/containers/${name}/root/nix/store:/nix/store"
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList
            (name: iface: ''
              NIXUNITS__ETH__${name}__HOST_IP4=${iface.hostIp4}
              NIXUNITS__ETH__${name}__HOST_IP6=${iface.hostIp6}
              NIXUNITS__ETH__${name}__IP4=${iface.ip4}
              NIXUNITS__ETH__${name}__IP6=${iface.ip6}
              NIXUNITS__ETH__${name}__OVS_BRIDGE=${iface.ovs.bridge}
              NIXUNITS__ETH__${name}__OVS_VLAN=${toString iface.ovs.vlan}
            '')
            cfg.network.interfaces
        )}
        IP4ROUTE=${cfg.network.ip4route}
        IP6ROUTE=${cfg.network.ip6route}
        NAME=${name}
        ${optionalString (extraFile != null) "EXTRA_FILE=${extraFile}"}
        ${optionalString (nftFile != null) "NFT_FILE=${nftFile}"}
        ${optionalString (sysctlFile != null) "SYSCTL_FILE=${sysctlFile}"}
        SYSTEM_PATH=${cfg.config.system.build.toplevel}
      '';
    };
  };

  conf = cfg: {
    environment.etc = mapAttrs' _conf_unit cfg;
  };

  security = import ./security.nix {inherit lib;};

in with lib; {
  inherit conf
    unitConf
    moduleName
    pathContainers pathRoot pathVar;
  options = {
    nixunits = mkOption {
      type = types.attrsOf (types.submodule (
        { config, options, name, ... }: {
          config = {
            nspawnArgs = (security.flags config.caps_allow) ++ [
              "--link-journal=host"
            ] ++ (map (_bind: "--bind=${_bind}") config.bind);
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

            bind = mkOption {
              default = [];
              type = types.listOf types.str;
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

            extra  = mkOption {
              default = "";
              type = types.str;
            };

            nspawnArgs = mkOption {
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
                  interfaces = mkOption {
                    default = {};
                    type = attrsOf (submodule {
                      options = {
                        hostIp4 = mkOption {
                          default = "";
                          type = str;
                        };
                        hostIp6 = mkOption {
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
                        ovs = mkOption {
                          default = {};
                          type = submodule {
                            options = {
                              bridge = mkOption {
                                default = "";
                                type = str;
                              };
                              vlan = mkOption {
                                default = 0;
                                type = int;
                              };
                            };
                          };
                        };
                      };
                    });
                  };
                  ip4route = mkOption {
                    default = "";
                    type = str;
                  };
                  ip6route = mkOption {
                    default = "";
                    type = str;
                  };
                  netns_path = mkOption {
                    default = "";
                    type = str;
                  };
                  nft = mkOption {
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

            nix_service_file = mkOption {
              type = str;
            };

            properties = mkOption {
              type = types.attrs;
              default = {};
              description = "";
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
            sysctl = mkOption {
              default = "";
              type = types.str;
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
