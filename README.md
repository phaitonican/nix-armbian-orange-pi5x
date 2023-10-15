# Flake to build an Armbian Image with Nix Package Manager (Hyprland and other user stuff)

## Overview

(Needs Aarch64 with Nix to build, didn't test on x86_64 yet)

To build the Image, use `nix build`. Flash the output .img.zstd file in the results folder to an SD-Card (see below). Boot the OrangePI 5x from that SD-Card. Copy the image onto SD-Card installation, and use the same process to flash it onto the eMMC drive (using LSBLK to identify).

## Spec

* Kernel 5.10.160 from [Armbian](https://github.com/armbian/linux-rockchip)
* U-boot - mainline 2023-07-02 with patch
* Panfork (for mesa 3D) v20.0.0 + mali firmware

Check `flake.nix` for more detail.

## Flash the image (SD-Card or eMMC, use lsblk to identify)

```bash
zstdcat result/sd-image/nixos-sd-image-*.img.zstd | sudo dd of=/dev/mmcblkX bs=4M status=progress
```

## Status

### Working

* Onchip IPs seem to work
* Ethernet
* GPU - on wayland (the `swaywm` included within sdcard image)
  * Start `sway` will then load Mali firmware, to check GPU accelleration, run firefox with Wayland enable `MOZ_ENABLE_WAYLAND=1 firefox`
    * `about:support` will show the status of GPU supporting
  * Perf is quite good - video playback consumed ~30% CPU (1080p youtube video on 4K monitor), ~50% CPU (4K youtube video on 4K monitor) - fullscreen mode
* USB-C OTG-mode
* Other? - not fully check (not that intrrested in :D)
* Audio

### Not working

* Wifi/BT
* USB2.0 port not working
* Vulkan/OpenGL doesnt seem to work? (SuperTuxKart and other games very laggy)
* Other??

## Ref.

* [Orange PI 5x work from Si Dao](https://github.com/fb87)
* [Initial work from Ryan Yin](https://github.com/ryan4yin/nixos-rk3588)

## Note:

* Image is able to build from my OPI-5B, might work on x86_64 machine (with binfmt supported).
* Needs Aarch64 with Nix to build, didn't test on x86_64 yet
