# Boots tidus's full system configuration in a QEMU VM and checks that it comes up.
# The qemu-vm module replaces tidus's disks, LUKS and bootloader with VM equivalents (as
# `nixos-rebuild build-vm` does), so this covers activation and services, not laptop hardware.
# Needs KVM: yuffie runs it as part of the nightly flake update gate.
{
  pkgs,
  inputs,
  modules,
}:
pkgs.testers.runNixOSTest {
  name = "tidus-boot";

  node.specialArgs = {inherit inputs;};
  # The host modules set nixpkgs.config and overlays, which a read-only pkgs rejects.
  node.pkgsReadOnly = false;

  nodes.tidus = {lib, ...}: {
    imports = modules;
    # The test driver reads the kernel console; tidus silences it for Plymouth.
    boot.consoleLogLevel = lib.mkForce 7;
    virtualisation = {
      memorySize = 3072;
      cores = 2;
      diskSize = 8192;
    };
  };

  testScript = ''
    # Units that fail only because the VM is not the real laptop.
    ALLOWED_FAILURES = {
        # The VM has no age key, so SOPS cannot decrypt any secret.
        "sops-install-secrets.service",
    }

    tidus.wait_for_unit("multi-user.target")
    tidus.wait_for_unit("home-manager-danny.service")
    tidus.wait_for_unit("docker.service")
    tidus.wait_for_unit("display-manager.service")

    failed = set(
        tidus.succeed(
            "systemctl list-units --state=failed --plain --no-legend | awk '{print $1}'"
        ).split()
    )
    unexpected = failed - ALLOWED_FAILURES
    assert not unexpected, f"failed units: {sorted(unexpected)}"
  '';
}
