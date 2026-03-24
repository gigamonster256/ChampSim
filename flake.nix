{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [ "x86_64-linux" ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      defaultChampsimSettings = lib.importJSON ./champsim_config.json;
      defaultSettingsWith = lib.recursiveUpdate defaultChampsimSettings;

      cores = lib.range 1 16;
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          champsim = pkgs.callPackage ./package.nix {
            champsimSettings = defaultChampsimSettings;
            # tests are kinda slow so skip
            doCheck = false;
          };
          champsimWithSettings =
            settings: champsim.override { champsimSettings = defaultSettingsWith settings; };
        in
        {
          # default package with default settings
          default = champsim;
          inherit champsim;
          # package with tests enabled
          with-tests = champsim.override { doCheck = true; };
          # package built with clang instead of gcc
          with-clang = champsim.override {
            stdenv = pkgs.clangStdenv;
            doCheck = true;
          };
          # overriding settings and executable name
          heartbeat = champsimWithSettings {
            executable_name = "champsim-heartbeat";
            heartbeat_frequency = 1;
          };
        }
        # make "champsim-N" packages for each core count
        // lib.genAttrs' cores (core: {
          name = "champsim-" + lib.toString core;
          value = champsimWithSettings {
            executable_name = "champsim-" + lib.toString core;
            num_cores = core;
          };
        })
        // {
          # make champsim_cores package that depends on all the champsim-N packages for easy installation of all cores
          # works beacuse each of the champsim-N binaries has a unique name so they won't conflict with each other
          # note that it can't be called "champsim-cores" since then it would try to include itself
          # (without rewriting the predicate of course)
          champsim_cores = pkgs.buildEnv {
            name = "champsim_cores";
            paths = lib.attrValues (
              lib.filterAttrs (
                name: _: lib.hasPrefix "champsim-" name
              ) self.packages.${pkgs.stdenv.hostPlatform.system}
            );
            # don't merge the share dirs since each package has its own config which will conflict
            pathsToLink = [ "/bin" ];
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
      devShells = forAllSystems (pkgs: {
        default = import ./shell.nix { inherit pkgs; };
        clang = import ./shell.nix {
          inherit pkgs;
          stdenv = pkgs.clangStdenv;
        };
      });
    };
}
