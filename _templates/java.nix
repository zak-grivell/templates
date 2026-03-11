{ pkgs, ... }:

{
  languages.java = {
    enable = true;
    maven.enable = true;
  };
}
