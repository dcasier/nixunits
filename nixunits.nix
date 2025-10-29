{ lib, pkgs, stdenv }: with lib;

stdenv.mkDerivation rec {
  pname = "nixunits";
  version = "0.1";

  src = ./.;

  buildPhase = with pkgs; ''
    mkdir -p $out/bin $out/nix $out/tests $out/unit
    cp $src/*.nix $out/
    cp $src/bin/* $out/bin/
    cp -r $src/nix/ $out/
    cp -r $src/tests/* $out/tests/
    cp -r $src/unit/* $out/unit/
    ln -s ../tests/nixunits_tests $out/bin/

    patchShebangs $out/bin

    sed -i "
      s|evalConfig=.*|evalConfig=$share/eval-config.nix|
      s|_NIXUNITS_PATH_SED_|$out|
      s|__AWK_BIN_SED__|${pkgs.gawk}/bin|
      s|__FIND_BIN_SED__|${pkgs.findutils}/bin|
      s|__GREP_BIN_SED__|${pkgs.gnugrep}/bin|
      s|__PSTREE_BIN_SED__|${pkgs.pstree}/bin|
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
