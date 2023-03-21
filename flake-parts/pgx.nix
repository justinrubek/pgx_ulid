{
  config,
  inputs,
  lib,
  self,
  ...
} @ part-inputs: {
  flake.lib = let
    extension = import ../packages/extension.nix part-inputs;
  in {
    buildPgxExtension = {
      pkgs,
      source,
      targetPostgres,
      additionalFeatures ? [],
      release ? true,
    }:
      extension {
        inherit source targetPostgres release additionalFeatures;
        inherit (inputs) naersk;
        inherit (inputs.pgx.packages.${pkgs.system}) cargo-pgx;
        inherit (self.packages.${pkgs.system}) rust-toolchain;
      };
  };

  perSystem = {
    config,
    pkgs,
    final,
    system,
    inputs',
    self',
    ...
  }: let
  in rec {
    overlayAttrs = {
      rust-bin.stable.latest.default = self'.packages.rust-toolchain;
    };

    devShells.default = pkgs.mkShell {
      buildInputs = [
        self'.packages.rust-toolchain
        self'.packages.postgresql

        inputs'.pgx.packages.cargo-pgx

        pkgs.libiconv
        pkgs.pkg-config
        pkgs.readline
        pkgs.zlib.dev
        pkgs.zlib.out
      ];

      LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
      PGX_PG_SYS_SKIP_BINDING_REWRITE = "1";
      BINDGEN_EXTRA_CLANG_ARGS =
        [
          ''-I"${pkgs.llvmPackages.libclang.lib}/lib/clang/${pkgs.llvmPackages.libclang.version}/include"''
        ]
        ++ (
          if pkgs.stdenv.isLinux
          then [
            "-I ${pkgs.glibc.dev}/include"
          ]
          else []
        );
    };

    packages = let
      extension = import ../packages/extension.nix part-inputs;
    in {
      pgx_ulid = extension {
        name = "pgx_ulid";
        pkgs = final;

        source = inputs.nix-filter.lib {
          root = ../.;
          include = [
            "src"
            "Cargo.toml"
            "Cargo.lock"
            "ulid.control"
          ];
        };

        targetPostgres = self'.packages.postgresql;
        release = false;

        inherit (inputs) naersk;
        inherit (inputs.pgx.packages.${pkgs.system}) cargo-pgx;
        inherit (self.packages.${pkgs.system}) rust-toolchain;
      };
    };
  };
}
