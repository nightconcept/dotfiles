{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            # Small BIOS boot partition for GRUB on GPT
            bios = {
              size = "1M";
              type = "EF02"; # BIOS boot partition type
              priority = 1;
            };
            root = {
              size = "100%";
              priority = 2;
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
