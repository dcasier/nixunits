{ lib, pkgs, stdenv }: with lib;

stdenv.mkDerivation rec {
  pname = "nixunits";
  version = "0.1";

  src = ./.;

  buildPhase = with pkgs; ''
    mkdir -p $out/bin $out/portable $out/services $out/tests $out/unit
    cp $src/*.nix $out/
    cp $src/bin/* $out/bin/
    cp $src/portable/* $out/portable/
    cp $src/tests/* $out/tests/
    cp $src/unit/* $out/unit/
    ln -s ../tests/nixunits_tests $out/bin/

    patchShebangs $out/bin

    sed -i "
      s|evalConfig=.*|evalConfig=$share/eval-config.nix|
      s|NIXUNITS|$out|
    " $out/bin/*

    sed -i "
      3i export PATH=${jq}/bin:${libcap}/bin:${iproute2}/bin:${procps}/bin:${coreutils-full}/bin:${util-linuxMinimal}/bin
      s|NIXUNITS|$out|
    " $out/unit/*
  '';

  meta = {
    homepage = "https://git.aevoo.com/aevoo/os/${pname}";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ maintainers.evoo ];
  };
  nativeBuildInputs = with pkgs; [ jq ];

  # phases = ["buildPhase"];
}
