{ lib }: with lib; let
  systemd = {
      # serviceConfig.NoNewPrivileges = mkForce null;
      # serviceConfig.ProtectSystem = "strict";
      # serviceConfig.ProtectHome = mkForce null;
      # serviceConfig.PrivateTmp = mkForce null;
      serviceConfig = {
        DynamicUser = mkForce false;
        PrivateDevices = mkForce null;
        PrivateMounts = mkForce null;
        ProtectHostname = mkForce null;
        ProtectKernelTunables = mkForce null;
        ProtectKernelModules = mkForce null;
        ProtectControlGroups = mkForce null;
        LockPersonality = mkForce null;
        MemoryDenyWriteExecute = mkForce null;
        RestrictAddressFamilies = mkForce null;
        RestrictNamespaces = mkForce null;
        RestrictRealtime = mkForce null;
        RestrictSUIDSGID = mkForce null;
        SystemCallArchitectures = mkForce null;
      };
  };
  cfgValid = cfg: let
    patch = ( if hasAttr "services" cfg then
      { systemd.services = mapAttrs (name: _: systemd) cfg.services; }
    else {});
  in
     recursiveUpdate cfg patch;
in {
  flags = cap_allow: let
    CAPS = subtractLists cap_allow [
    # "CAP_DAC_OVERRIDE"
    # "CAP_SETFCAP"
    # "CAP_SETPCAP"
      "CAP_AUDIT_WRITE"
      "CAP_AUDIT_CONTROL"
      "CAP_DAC_READ_SEARCH"
      "CAP_IPC_LOCK"
      "CAP_IPC_OWNER"
      "CAP_LEASE"
      "CAP_LINUX_IMMUTABLE"
      "CAP_MAC_OVERRIDE"
      "CAP_MKNOD"
      "CAP_NET_ADMIN"
      "CAP_NET_BROADCAST"
      "CAP_NET_RAW"
      "CAP_SYS_NICE"
      "CAP_SYS_ADMIN"
      "CAP_SYS_BOOT"
      "CAP_SYS_MODULE"
      "CAP_SYS_RAWIO"
      "CAP_SYS_PTRACE"
      "CAP_SYS_PACCT"
      "CAP_SYS_NICE"
      "CAP_SYS_RESOURCE"
      "CAP_SYS_TIME"
      "CAP_SYS_TTY_CONFIG"
    ];
  in [
    "--no-new-privileges=yes"
    "--private-users=pick"
    "--private-users-chown"
  ]
  ++ map (cap: "--drop-capability=${cap}") CAPS
  ++ map (cap: "--capability=${cap}") cap_allow;
  inherit cfgValid systemd;
}

#  systemd.services= {
#    journald.serviceConfig = {
#      DynamicUser = lib.mkForce false;
#      PrivateDevices = lib.mkForce null;
#      PrivateMounts = lib.mkForce null;
#      ProtectHostname = lib.mkForce null;
#      ProtectKernelTunables = lib.mkForce null;
#      ProtectKernelModules = lib.mkForce null;
#      ProtectControlGroups = lib.mkForce null;
#      LockPersonality = lib.mkForce null;
#      MemoryDenyWriteExecute = lib.mkForce null;
#      RestrictAddressFamilies = lib.mkForce null;
#      RestrictNamespaces = lib.mkForce null;
#      RestrictRealtime = lib.mkForce null;
#      RestrictSUIDSGID = lib.mkForce null;
#      SystemCallArchitectures = lib.mkForce null;
#    };
#    systemd-journald.serviceConfig = {
#      DynamicUser = lib.mkForce false;
#      PrivateDevices = lib.mkForce null;
#      PrivateMounts = lib.mkForce null;
#      ProtectHostname = lib.mkForce null;
#      ProtectKernelTunables = lib.mkForce null;
#      ProtectKernelModules = lib.mkForce null;
#      ProtectControlGroups = lib.mkForce null;
#      LockPersonality = lib.mkForce null;
#      MemoryDenyWriteExecute = lib.mkForce null;
#      RestrictAddressFamilies = lib.mkForce null;
#      RestrictNamespaces = lib.mkForce null;
#      RestrictRealtime = lib.mkForce null;
#      RestrictSUIDSGID = lib.mkForce null;
#      SystemCallArchitectures = lib.mkForce null;
#    };