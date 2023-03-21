{...} @ part-inputs: {
  imports = [];

  perSystem = {
    pkgs,
    self',
    ...
  }: let
    init-database = pkgs.writeScriptBin "init-database" ''
      set -euo pipefail

      ${self'.packages.postgresql}/bin/initdb -D .tmp/test-db
      ${self'.packages.postgresql}/bin/pg_ctl -D .tmp/test-db -l .tmp/test-db.log -o "--unix_socket_directories='$PWD'" start
      ${self'.packages.postgresql}/bin/createdb test-db -h $PWD
    '';

    start-database = pkgs.writeScriptBin "start-database" ''
      set -euo pipefail

      ${self'.packages.postgresql}/bin/pg_ctl -D .tmp/test-db -l .tmp/test-db.log -o "--unix_socket_directories='$PWD'" start
    '';

    stop-database = pkgs.writeScriptBin "stop-database" ''
      set -euo pipefail

      ${self'.packages.postgresql}/bin/pg_ctl -D .tmp/test-db stop
    '';
  in rec {
    packages = rec {
      postgresql_target = pkgs.postgresql_15;
      postgresql = postgresql_target.withPackages (ps: with ps; [self'.packages.pgx_ulid]);

      "scripts/init-database" = init-database;
      "scripts/start-database" = start-database;
      "scripts/stop-database" = stop-database;
    };
  };
}
