{ lib, rustPlatform, cmake }:

rustPlatform.buildRustPackage {
  pname = "rosimbot-gateway";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./src ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  # aws-lc-sys (rustls crypto backend) builds C code; stdenv already has cc.
  nativeBuildInputs = [ cmake ];

  meta.mainProgram = "rosimbot-gateway";
}
