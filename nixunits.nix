{ lib, pkgs, stdenv, rev ? "unknown" }: with lib;

stdenv.mkDerivation rec {
  pname = "nixunits";
  version = "0.2.5";

  src = ./.;

  buildPhase = with pkgs; ''
    mkdir -p $out/bin $out/nix $out/tests $out/unit
    cp $src/flake.lock $out/
    cp $src/*.nix $out/
    cp $src/bin/* $out/bin/
    cp -r $src/nix/ $out/
    cp -r $src/tests/* $out/tests/
    cp -r $src/unit/* $out/unit/
    ln -fs ../tests/nixunits_tests $out/bin/

    patchShebangs $out/bin

    nixpkgsRev=$(jq -r '.nodes.nixpkgs.locked.rev' $src/flake.lock)
    # Sources that generate the container (nix/*.nix, see mkContainer)
    genHash=$(cd $src && find nix -maxdepth 1 -type f -name '*.nix' -print0 \
      | sort -z | xargs -0 sha1sum | sha1sum | cut -d' ' -f1)

    sed -i "
      s|_SYSTEM_SED_|${pkgs.stdenv.hostPlatform.system}|
      s|_NIXUNITS_VERSION_SED_|${version}|
      s|_NIXUNITS_REV_SED_|${rev}|
      s|_NIXUNITS_GEN_HASH_SED_|$genHash|
      s|_NIXPKGS_REV_SED_|$nixpkgsRev|
      s|evalConfig=.*|evalConfig=$share/eval-config.nix|
      s|_NIXUNITS_PATH_SED_|$out|
      s|__AWK_BIN_SED__|${pkgs.gawk}/bin|
      s|__FIND_BIN_SED__|${pkgs.findutils}/bin|
      s|__GREP_BIN_SED__|${pkgs.gnugrep}/bin|
      s|__INOTIFY_BIN_SED__|${pkgs.inotify-tools}/bin|
      s|__PSTREE_BIN_SED__|${pkgs.pstree}/bin|
      s|__SYSTEMD_BIN_SED__|${pkgs.systemd}/bin|
      s|_JQ_SED_|${pkgs.jq}/bin/jq|
    " $out/bin/*

    sed -i "
      3i export PATH=${jq}/bin:${libcap}/bin:${iproute2}/bin:${procps}/bin:${coreutils-full}/bin:${util-linuxMinimal}/bin
      s|_NIXUNITS_PATH_SED_|$out|
      s|_OPENVSWITCH_PATH_SED_|${pkgs.openvswitch}|
      s|_NFT_BIN_SED_|${pkgs.nftables}/bin/nft|
    " $out/unit/*
  '';

  meta = {
    homepage = "https://git.aevoo.com/aevoo/os/${pname}";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ maintainers.evoo ];
  };
  nativeBuildInputs = with pkgs; [ jq yq ];

  # phases = ["buildPhase"];
}
