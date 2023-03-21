{
  lib,
  stdenv,
  fetchCrate,
  rustPlatform,
  pkg-config,
  openssl,
  ...
}:
# https://github.com/NixOS/nixpkgs/issues/107070#issuecomment-1120372429
rustPlatform.buildRustPackage rec {
  pname = "cargo-pgx";
  version = "0.7.3";

  src = fetchCrate {
    inherit version pname;
    sha256 = "sha256-5YkNegug5gG2hnASdG6gTVxeY/VVQt/RieSlSgPKs2s=";
  };

  cargoSha256 = "DCvJYsFyFVGcw/zsm20Ja34XOEH0cqNDZjEJOkd/+/0=";

  nativeBuildInputs = [pkg-config];

  buildInputs = [openssl];

  meta = with lib; {
    description = "Cargo subcommand for ‘pgx’ to make Postgres extension development easy";
    homepage = "https://github.com/tcdi/pgx/tree/v${version}/cargo-pgx";
    license = licenses.mit;
    maintainers = with maintainers; [typetetris];
  };
}
