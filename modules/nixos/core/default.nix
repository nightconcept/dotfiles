# Core NixOS modules - essential system configuration
{
  imports = [
    ./bootloader
    ./nix
    ./lix
    ./locale
    ./users
    ./packages
  ];
}
