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
          inherit (pkgs.stdenv.hostPlatform) system;
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
          champsim_cores =
            pkgs.buildEnv {
              name = "champsim_cores";
              paths = lib.attrValues (
                lib.filterAttrs (
                  name: _: lib.hasPrefix "champsim-" name
                ) self.packages.${system}
              );
              # don't merge the share dirs since each package has its own config which will conflict
              pathsToLink = [ "/bin" ];
            };
            # runnable simulation
        } 
        // (
              let
                perlbench = pkgs.fetchurl {
                  url = "https://dpc3.compas.cs.stonybrook.edu/champsim-traces/speccpu/400.perlbench-41B.champsimtrace.xz";
                  hash = "sha256-GvLlsJOSDi/BUjcsBVNlgTCTHozPOtoEF13ofkCK8JE=";
                };
                script = name: champsim: {warmup, simulation}: pkgs.writeShellScript name ''
                  ${lib.getExe champsim} -w${lib.toString warmup} -i${lib.toString simulation} -- ${perlbench}
                '';
                artifact = name: champsim: {warmup, simulation}: pkgs.runCommand name { } ''
                  ${lib.getExe champsim} -w${lib.toString warmup} -i${lib.toString simulation} --json=$out -- ${perlbench}
                '';
              in
              {
                # make a script that runs champsim
                perlbench-script = script "perlbench-script" champsim {
                  warmup = 50000000;
                  simulation = 50000000;
                };
                # run a script that runs champsim and produces a json output
                perlbench-artifact = artifact "perlbench-artifact" champsim {
                  warmup = 50000000;
                  simulation = 50000000;
                };
              }
            )
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
