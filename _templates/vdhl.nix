{ pkgs, ... }:

{
  packages = with pkgs; [
    vhdl-ls
    surfer
  ];
}
