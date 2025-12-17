# inspired by erikarvstedt/extra-container

{ lib, options, ... }:

let
    optionValue = default: lib.mkOption { inherit default; };
    dummy = optionValue [];
    False = optionValue false;
    True = optionValue true;
in {
    options = {
      boot = {
        kernel.sysctl = dummy;
        kernelModules = dummy;
        kernelPackages.kernel.version = optionValue "";
        kernelParams = dummy;
        loader.systemd-boot.bootCounting.enable = False;
      };
      environment.systemPackages = dummy;
      networking = {
        dhcpcd.denyInterfaces = dummy;
        extraHosts = dummy;
        proxy.envVars = optionValue {};
      };
      security = {
        polkit = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
        };
        pam = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          services = lib.mkOption {
            type = lib.types.attrs;
            default = {};
          };
        };
      };
      services = {
        dbus = dummy;
        logrotate = dummy;
        rsyslogd.enable = False;
        syslog-ng.enable = False;
        udev = dummy;
      };
      system = {
        activationScripts = dummy;
        fsPackages = dummy;
        nscd = dummy;
        nssDatabases = dummy;
        nssModules = dummy;
        path = optionValue "";
        requiredKernelConfig = dummy;
        stateVersion = optionValue "25.11";
      };
      systemd = {
        oomd = dummy;
        user.generators = optionValue {};
      };
      ids = {
          gids = {
            keys = dummy;
            systemd-journal = dummy;
            systemd-journal-gateway = dummy;
            systemd-network = dummy;
            systemd-resolve = dummy;
          };
          uid = {
            systemd-coredump = dummy;
            systemd-journal-gateway = dummy;
            systemd-network = dummy;
            systemd-resolve = dummy;
          };
      };
      users = {
        groups = {
            systemd-coredump = dummy;
            systemd-network.gid = dummy;
            systemd-resolve.gid = dummy;
            keys.gid = dummy;
            systemd-journal.gid = dummy;
            systemd-journal-gateway.gid = dummy;
        };
        users = {
            systemd-coredump = dummy;
            systemd-network.group = dummy;
            systemd-network.uid = dummy;
            systemd-resolve.group = dummy;
            systemd-resolve.uid = dummy;
            systemd-journal-gateway.group = dummy;
            systemd-journal-gateway.uid = dummy;
          };
        };
    };

    config = {
      systemd.timers = lib.mkForce {};
      systemd.targets = lib.mkForce {};
    } // lib.optionalAttrs (options.systemd ? managerEnvironment) {
      systemd.managerEnvironment = lib.mkForce {};
    };
}