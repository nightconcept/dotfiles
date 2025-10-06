# Custom library functions for the flake
{
  lib,
  inputs,
  snowfall-inputs,
  ...
}: {
  # Custom module helper functions
  module = import ./module {inherit lib;};
}
