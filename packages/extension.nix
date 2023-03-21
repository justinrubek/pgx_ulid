{
  config,
  inputs,
  lib,
  self,
  ...
} @ part-inputs: {
  name,
  pkgs,
  cargo-pgrx,
  rust-toolchain,
  targetPostgres,
  naersk,
  source,
  release ? true,
  additionalFeatures ? [],
  doCheck ? true,
}: let
  # TODO: Ensure the .control file is present in the output
  # TODO: remove naersk usage and clean up
  # TODO: expose the extension functionality in a way that allows for specifying the postgres version
  # leftover for naersk implementation
  inherit (pkgs) stdenv clangStdenv hostPlatform targetPlatform pkg-config openssl libiconv rust-bin llvmPackages runCommand;
  system = pkgs.system;

  maybeReleaseFlag =
    if release == true
    then "--release"
    else "";
  maybeDebugFlag =
    if release == true
    then ""
    else "--debug";
  pgxPostgresMajor = builtins.head (lib.splitString "." targetPostgres.version);
  cargoToml = builtins.fromTOML (builtins.readFile "${source}/Cargo.toml");
  preBuildAndTest = ''
    export PGRX_HOME=$(mktemp -d)
    mkdir -p $PGRX_HOME/${pgxPostgresMajor}

    cp -r -L ${targetPostgres}/. $PGRX_HOME/${pgxPostgresMajor}/
    chmod -R ugo+w $PGRX_HOME/${pgxPostgresMajor}
    cp -r -L ${targetPostgres.lib}/lib/. $PGRX_HOME/${pgxPostgresMajor}/lib/

    echo "About to call cargo-pgrx init"
    ${cargo-pgrx}/bin/cargo-pgrx pgrx init \
      --pg${pgxPostgresMajor} $PGRX_HOME/${pgxPostgresMajor}/bin/pg_config \

    # This is primarily for Mac or other Nix systems that don't use the nixbld user.
    export USER=$(whoami)
    export PGDATA=$PGRX_HOME/data-${pgxPostgresMajor}/
    export NIX_PGLIBDIR=$PGRX_HOME/${pgxPostgresMajor}/lib

    echo "starting postgres and creating user"
    echo "unix_socket_directories = '$(mktemp -d)'" > $PGDATA/postgresql.conf
    ${targetPostgres}/bin/pg_ctl start
    ${targetPostgres}/bin/createuser -h localhost --superuser --createdb $USER || true
    ${targetPostgres}/bin/pg_ctl stop
    echo "postgres stopped"

    # Set C flags for Rust's bindgen program. Unlike ordinary C
    # compilation, bindgen does not invoke $CC directly. Instead it
    # uses LLVM's libclang. To make sure all necessary flags are
    # included we need to look in a few places.
    # TODO: generalize this process for other use-cases.
    export BINDGEN_EXTRA_CLANG_ARGS="$(< ${stdenv.cc}/nix-support/libc-crt1-cflags) \
      $(< ${stdenv.cc}/nix-support/libc-cflags) \
      $(< ${stdenv.cc}/nix-support/cc-cflags) \
      $(< ${stdenv.cc}/nix-support/libcxx-cxxflags) \
      ${lib.optionalString stdenv.cc.isClang "-idirafter ${stdenv.cc.cc}/lib/clang/${lib.getVersion stdenv.cc.cc}/include"} \
      ${lib.optionalString stdenv.cc.isGNU "-isystem ${stdenv.cc.cc}/include/c++/${lib.getVersion stdenv.cc.cc} -isystem ${stdenv.cc.cc}/include/c++/${lib.getVersion stdenv.cc.cc}/${stdenv.hostPlatform.config} -idirafter ${stdenv.cc.cc}/lib/gcc/${stdenv.hostPlatform.config}/${lib.getVersion stdenv.cc.cc}/include"}
    "
  '';

  naerskPackage = naersk.lib."${targetPlatform.system}".buildPackage rec {
    inherit release doCheck;
    name = "${cargoToml.package.name}-pg${pgxPostgresMajor}";
    version = cargoToml.package.version;

    src = source;

    inputsFrom = [targetPostgres cargo-pgrx];

    LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";
    buildInputs = [
      rust-toolchain
      cargo-pgrx
      pkg-config
      libiconv
      targetPostgres
    ];
    checkInputs = [
      cargo-pgrx
      rust-toolchain
    ];

    postPatch = "patchShebangs .";
    preBuild = preBuildAndTest;
    preCheck = preBuildAndTest;
    postBuild = ''
      if [ -f "${cargoToml.package.name}.control" ]; then
        export NIX_PGLIBDIR=${targetPostgres.out}/share/postgresql/extension/
        echo "About to call cargo-pgrx pgrx package"
        ${cargo-pgrx}/bin/cargo-pgrx pgrx package --pg-config ${targetPostgres}/bin/pg_config ${maybeDebugFlag} --features "${builtins.toString additionalFeatures}" --out-dir $out
        echo "Package complete"
        export NIX_PGLIBDIR=$PGRX_HOME/${pgxPostgresMajor}/lib
      fi
    '';
    # Certain extremely slow machines (Github actions...) don't clean up their socket properly.
    preFixup = ''
      if [ -f "${cargoToml.package.name}.control" ]; then
        ${cargo-pgrx}/bin/cargo-pgrx pgrx stop all

        mv -v $out/${targetPostgres.out}/* $out
        rm -rfv $out/nix
      fi
    '';

    PGRX_PG_SYS_SKIP_BINDING_REWRITE = "1";
    CARGO_BUILD_INCREMENTAL = "false";
    RUST_BACKTRACE = "full";

    cargoBuildOptions = default: default ++ ["--no-default-features" "--features \"pg${pgxPostgresMajor} ${builtins.toString additionalFeatures}\""];
    cargoTestOptions = default: default ++ ["--no-default-features" "--features \"pg_test pg${pgxPostgresMajor} ${builtins.toString additionalFeatures}\""];
    doDoc = false;
    copyLibs = false;
    copyBins = false;

    meta = with lib; {
      description = cargoToml.package.description;
      homepage = cargoToml.package.homepage;
      license = with licenses; [mit];
      maintainers = with maintainers; [hoverbear];
    };
  };

  # Now, perform the above steps from naersk, but instead use crane

  # packages needed for building
  extraPackages = [
    pkgs.pkg-config
    pkgs.libiconv
    targetPostgres.lib
    targetPostgres
  ];
  withExtraPackages = base: base ++ extraPackages;

  craneLib = inputs.crane.lib.${system}.overrideToolchain self.packages.${system}.rust-toolchain;

  common-build-args = rec {
    src = source;

    pname = "${name}-pg${pgxPostgresMajor}";

    nativeBuildInputs = withExtraPackages [];
    LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath nativeBuildInputs;

    LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";

    postPatch = "patchShebangs .";
    preBuild = preBuildAndTest;
    preCheck = preBuildAndTest;
    postBuild = ''
      if [ -f "${name}.control" ]; then
        export NIX_PGLIBDIR=${targetPostgres.out}/share/postgresql/extension/
        echo "About to call cargo-pgrx pgrx package"
        ${cargo-pgrx}/bin/cargo-pgrx pgrx package --pg-config ${targetPostgres}/bin/pg_config ${maybeDebugFlag} --features "${builtins.toString additionalFeatures}" --out-dir $out
        echo "Package complete"
        export NIX_PGLIBDIR=$PGRX_HOME/${pgxPostgresMajor}/lib
      fi
    '';

    PGRX_PG_SYS_SKIP_BINDING_REWRITE = "1";
    CARGO_BUILD_INCREMENTAL = "false";
    RUST_BACKTRACE = "full";

    cargoExtraArgs = "--no-default-features --features \"pg${pgxPostgresMajor} ${builtins.toString additionalFeatures}\"";
  };

  deps-only = craneLib.buildDepsOnly ({} // common-build-args);

  cranePackage = craneLib.mkCargoDerivation ({
      pname = "${name}-pg${pgxPostgresMajor}";
      cargoArtifacts = deps-only;
      doCheck = false;
      postBuild = common-build-args.postBuild;
      buildPhaseCargoCommand = ''
        cargoBuildLog=$(mktemp cargoBuildLogXXXX.json)
        cargoWithProfile build --message-format json-render-diagnostics > $cargoBuildLog

        ${cargo-pgrx}/bin/cargo-pgrx pgrx package --pg-config ${targetPostgres}/bin/pg_config ${maybeDebugFlag} --features "${builtins.toString additionalFeatures}" --out-dir $out
      '';

      preFixup = ''
        if [ -f "${name}.control" ]; then
          ${cargo-pgrx}/bin/cargo-pgrx pgrx stop all

          # Clean up the build directory
          # Copy the .control and .sql files to $out, then remove the excess
          mv -v $out/${targetPostgres.out}/* $out
          rm -rfv $out/nix

        fi
      '';

      postInstall = ''
        # copy the .so files to $out/lib
        mkdir -p $out/lib
        cp target/release/libulid.so $out/lib/ulid.so

        # Copy the contents of $out/${targetPostgres.out}/* to $out, then remove $out/${targetPostgres.out}
        ${cargo-pgrx}/bin/cargo-pgrx pgrx stop all

        mv -v $out/${targetPostgres.out}/* $out
        rm -rfv $out/nix
        rm -rfv $out/build
        rm -rfv $out/target
      '';
    }
    // common-build-args);
  # in naerskPackage

  # filter out unwanted directoryes
  filted-derivation = pkgs.stdenv.mkDerivation {
    name = "${name}-pg${pgxPostgresMajor}";
    buildInputs = [cranePackage];
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out
      cp -r ${cranePackage}/lib $out
      cp -r ${cranePackage}/share $out
    '';
  };
in
  filted-derivation
