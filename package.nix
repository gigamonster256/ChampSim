{
  lib,
  stdenv,
  python3,
  cli11,
  nlohmann_json,
  fmt,
  bzip2,
  xz,
  zlib,
  catch2_3,
  champsimSettings ? null,
  doCheck ? stdenv.buildPlatform.canExecute stdenv.hostPlatform,
}:
let
  hasChampsimSettings = champsimSettings != null;
  champsimConfig = lib.optionalString hasChampsimSettings (
    builtins.toFile "champsim_config.json" (builtins.toJSON champsimSettings)
  );
in
stdenv.mkDerivation (finalAttrs: {
  pname = "champsim";
  version = "1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.intersection (lib.fileset.fromSource (lib.sources.cleanSource ./.)) (
      lib.fileset.unions [
        # setup
        ./config
        ./config.sh
        # compilation
        ./Makefile
        ./global.options
        ./module.options
        ./inc
        ./src
        # modules
        ./branch
        ./btb
        ./prefetcher
        ./replacement
        # tests
        ./test
      ]
    );
  };

  nativeBuildInputs = [
    python3
    cli11 # header only
    nlohmann_json # header only
  ];

  buildInputs = [
    fmt
    bzip2
    xz
    zlib
  ];

  patchPhase = ''
    runHook prePatch

    # patch Makefile use header only cli11
    substituteInPlace Makefile \
      --replace-fail "-lCLI11" ""

    # patch tests to use catch2 not in single header mode
    substituteInPlace test/cpp/src/*.cc \
      --replace-quiet "<catch.hpp>" "<catch2/catch_all.hpp>"

    runHook postPatch
  '';

  configurePhase = ''
    runHook preConfigure

    python3 ./config.sh ${champsimConfig}

    # setup absolute.options
    echo "-I${finalAttrs.src}/inc" > absolute.options

    runHook postConfigure
  '';

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -r bin/* $out/bin/
  ''
  # copy champsim config for reference if settings were provided
  + lib.optionalString hasChampsimSettings ''

    mkdir -p $out/share/champsim
    cp "${champsimConfig}" $out/share/champsim/config.json
  ''
  + ''
    runHook postInstall
  '';

  nativeCheckInputs = [
    catch2_3
  ];

  inherit doCheck;

  meta.mainProgram =
    if hasChampsimSettings then (champsimSettings.executable_name or "champsim") else "champsim";
})
