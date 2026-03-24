{
  pkgs ? import <nixpkgs> { },
}:
(pkgs.mkShell.override { stdenv = pkgs.clangStdenv; }) {
  
  nativeBuildInputs = [
    pkgs.python3
    pkgs.vcpkg
    pkgs.pkg-config
  ];

  shellHook = ''
    export NIX_VCPKG_INSTALL_ROOT=$PWD/vcpkg_installed
    if [ ! -d "$NIX_VCPKG_INSTALL_ROOT/vcpkg" ]; then
      echo "Bootstrapping vcpkg..."
      vcpkg install
    fi
  '';
}
