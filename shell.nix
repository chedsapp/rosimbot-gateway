{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  nativeBuildInputs = [ pkgs.gcc pkgs.cmake pkgs.pkg-config ];
}
