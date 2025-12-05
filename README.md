# NixUnits

Run **NixOS** services in **lightweight**, **declarative**, and **isolated** containers.

Inspired by **nixos-container** and **extra-container**,
initially designed for Aevoo and usable on any Linux systemd host.

## Features

NixUnits allows running NixOS on any Linux systemd host, with per-service isolation,
while keeping a fully declarative configuration model.

* **Nix**  
  The service runs in a minimal and reproducible system environment.
* Based on **NixOS/nixpkgs** for building the image
* **systemd-nspawn** on the host  
  Orchestration via `systemctl` and `machinectl`.
* **Shared overlay Nix store**  
  Minimal duplication between containers.
* **Configurable network**  
  Interfaces, IPs, OVS, VLAN, netns, routes.
* **Explicit security**  
  Capabilities controlled by the Nix declaration.
* Minimal footprint: **systemd-minimal** and limited dependencies.


> What is declared is what is executed.

---

## Memory footprint and processes

A NixUnits container usually runs:

* systemd-minimal (PID1)
* container journald  
* the main service + auxiliary processes

Removed:  
✗ logind  
✗ getty  
✗ user-sessions  
✗ coredumpd  
✗ other unneeded systemd services for a container workload

> Sufficient to orchestrate a full service.  

Low structural overhead.

> Limited cost for a NixUnits container

---

## Installation

### NixOS

In `flake.nix`:

```nix
{
  inputs.nixunits.url = "github:.../nixunits";

  outputs = { self, nixunits, nixpkgs, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        nixunits.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

or:

```nix
environment.systemPackages = [
  nixunits.packages.${system}.nixunits
];
```

### Debian + Nix

* Dependency: systemd-container
* Dependencies on a non-NixOS infra are handled through the Nix store.
* Development is started from NixOS and tested on Debian: issues/bugs may exist => contact@aevoo.fr

```bash
nix run github:dcasier/nixunits#portable
```

---

## Quick start


**web2.json**
```json
{
  "id": "web2",
  "ip4": "192.168.20.2/31",
  "hostIp4": "192.168.20.1/31"
}
```

**web_default.nix**
```nix
{ pkgs, properties, lib, ... }: let 
  get = path: default: lib.attrByPath path default properties;
  ip4     = get [ "ip4" ]             "10.0.0.2/31";
  hostIp4 = get [ "hostIp4" ]         "10.0.0.1/31";
in {
  caps_allow = [ "CAP_NET_BIND_SERVICE" ];

  network.interfaces.veth = {
    inherit ip4 hostIp4;
  };

  config = {
    services.httpd.enable = true;
    system.stateVersion = "25.11";
  };
}
```

Build + start:

```bash
nixunits build -n ./web_default.nix -j ./web2.json -s
```

Inspection:

```bash
journalctl -M web2 -b
journalctl -u nixunits@web2 -f
journalctl -M web2 -u httpd
nixunits shell web2
```

---

## Architecture

```
Host (Linux systemd)
 └─ systemd-nspawn (machine.slice)
     ├─ /var/lib/nixunits/store/default/root  ← base NixOS ro
     └─ /var/lib/nixunits/containers/<id>/
         ├─ root/     ← writable
         ├─ (work/)
         ├─ (merged/)
         └─ unit.conf ← runtime parameters generated
```

Build cycle:

1. base build (default store)
2. overlay and final build (container properties)

---

## Important

### Build and overlay

Container-specific parameters (IP, names, …) must be provided via properties.json.
The content of config.nix will be included in the shared store (by default) for other containers.

> This does not affect **secret management**, which remains identical to a standard Nix configuration.

Example:

✓ Correct (container-specific data)
```json
{ "ip4": "10.0.0.2/31" }
```

✗ Incorrect (stored in shared store)
```nix
network.interfaces.veth.ip4 = "10.0.0.2/31";
```


### Container “PID 1” but **minimalistic**

systemd is only responsible for ensuring the proper operation of services and log management.

> D-Bus is not provided by default in a NixUnits container.

Enabled:
 - Log management (from host or container)
 - Service/process management inside the container (stop, restart, …)
 - Basic systemd services

## Advanced example

**properties.json**
```json
{
  "id": "router1",
  "bridge":  "br0",
  "ip4": "10.0.0.2/16",
  "ip6":  "a:b:c:d::e/64",
  "vlan": 4356,
  "bridgeWan":  "br0",
  "ip4Wan": "70.0.0.2/31",
  "ip6Wan":  "2001:bc8::a/64",
  "vlanWan": 356,
  "ip4route":  "20.0.0.254",
  "ip6route": "2001:bc8::ffff:ffff:ffff:fffe"
}
```

**config.nix**
```nix
{ pkgs, properties, lib, ... }: let 
  get = path: default: lib.attrByPath path default properties;
  bridge    = get [ "bridge" ]     "br0";
  ip4       = get [ "ip4" ]        "192.168.0.2/24";
  ip6       = get [ "ip6" ]        "a:b:c:d::e/64";
  vlan      = get [ "vlan" ]        4356;
  bridgeWan = get [ "bridgeWan" ]  "br0";
  ip4Wan    = get [ "ip4Wan" ]     "20.0.0.2/31";
  ip6Wan    = get [ "ip6Wan" ]     "fe80::a/64";
  vlanWan   = get [ "vlanWan" ]     356;
  ip4route  = get [ "ip4route" ]   "20.0.0.254";
  ip6route  = get [ "ip6route" ]   "fe80::ffff:ffff:ffff:fffe";
in {
  bind = [
    "/srv/logs:/var/log/service:ro"
  ];
  caps_allow = [ "CAP_NET_ADMIN" ];

  config = {
    networking.firewall.enable = false;
    services.dnsmasq.enable = true;
    system.stateVersion = "25.11";
  };
  extra = ''
    # Content evaluated by /bin/sh inside the container
  '';
  # netns_path = # incompatible with interface declaration and with "private-user" (cf. systemd-nspawn docs) 

  network = {
    interfaces = {
        lan = {
          inherit ip4 ip6;
          ovs = {
            inherit bridge vlan;
          };
        };
        wan = {
          ip4 = ip4Wan;
          ip6 = ip6Wan;
          ovs = {
            bridge = bridgeWan;
            vlan = vlanWan;
          };
        };
    };
    nft = ''
        table inet filter {
          chain input {
            type filter hook input priority 0;
            accept
          }
        }
    '';  
    inherit ip4route ip6route;
  };
  nspawnArgs = ""; # systemd-nspawn args 
  sysctl = ''
    net.ipv4.ip_forward=1
  '';
}
```

> Definitions declared in nix/global.nix

---

## Limitations

This project is **experimental**.
Some network features require prior configuration on the host:

| Feature | Requirement |
|---------|------------|
| Network interfaces | veth, OVS, bridge, netns configured |
| OVS / VLAN | openvswitch installed |
| nft | nftables active |
| netns_path | ip netns (or equivalent) |

Except for OVS/private-network, nixUnits **does not automate** host network provisioning.

## Docker / Podman vs NixUnits comparison

| Criterion | Docker / Podman | NixUnits |
|----------|----------------|----------|
| Target | Containerized apps | Isolated NixOS services |
| Build | Dockerfile / OCI | Nix derivations (declarative) |
| Distribution | Image registries | Nix source + store |
| System inside container | Systemd not necessary | systemd-minimal |
| Orchestration | Docker CLI, compose, K8s | Aevoo, systemctl, machinectl (or NixOS declarative) |
| Security | Runtime configuration | Declarative (Nix) |
| Portability | portable | Linux systemd only |
| Usage model | Dev & CI, app portability | Ops Nix on systemd infra |

NixUnits does not aim to replace Docker/Podman.
It is designed to run **NixOS services** (Aevoo marketplace) isolated on a Linux systemd host,
with network control and fully declarative configuration.

---

## CLI

```
nixunits <action> [options]
```

| Action | Effect |
|--------|--------|
| build <id> | create or update the container |
| start / restart / status | systemd service control |
| shell / nsenter | enter the container |
| list | declared and active containers |
| delete <id> | remove the container |
| * | wrapper around machinectl $@ |

---

## Troubleshooting

* nix build `-d` enables `--show-trace`
* Tested under Debian and NixOS
* Log management via `journalctl -M <machineID>`
* For any question: contact@aevoo.fr

## Declarative security

* User Namespace enabled unless `netns_path` is specified
* Explicit capabilities

```nix
caps_allow = [ "CAP_NET_BIND_SERVICE" ];
```

> Strict policy by default, voluntary opening.

---
