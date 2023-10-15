{
  description = "NixOS Installer AArch64";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05-small";

    mesa-panfork = {
      url = "gitlab:panfork/mesa/csf";
      flake = false;
    };

    linux-rockchip = {
      url = "github:armbian/linux-rockchip/rk-5.10-rkr5.1";
      flake = false;
    };
  };

  outputs = inputs@{ nixpkgs, ... }:
    let

      pkgs = import nixpkgs { system = "aarch64-linux"; };
      rkbin = pkgs.stdenvNoCC.mkDerivation {
        pname = "rkbin";
        version = "unstable-b4558da";

        src = pkgs.fetchFromGitHub {
          owner = "rockchip-linux";
          repo = "rkbin";
          rev = "b4558da0860ca48bf1a571dd33ccba580b9abe23";
          sha256 = "sha256-KUZQaQ+IZ0OynawlYGW99QGAOmOrGt2CZidI3NTxFw8=";
        };

        # we just need TPL and BL31 but it doesn't hurt,
        # follow single point of change to make life easier
        installPhase = ''
          mkdir $out && cp bin/rk35/rk3588* $out/
        '';
      };

      u-boot = pkgs.stdenv.mkDerivation rec {
        pname = "u-boot";
        version = "v2023.07.02";

        src = pkgs.fetchFromGitHub {
          owner = "u-boot";
          repo = "u-boot";
          rev = "${version}";
          sha256 = "sha256-HPBjm/rIkfTCyAKCFvCqoK7oNN9e9rV9l32qLmI/qz4=";
        };

        # u-boot for evb is not enable the sdmmc node, which cause issue as
        # b-boot cannot detect sdcard to boot from
        # the order of boot also need to swap, the eMMC mapped to mm0 (not same as Linux kernel)
        # will then tell u-boot to load images from eMMC first instead of sdcard
        # FIXME: this is strage cuz the order seem correct in Linux kernel
        patches = [ ./patches/u-boot/0001-sdmmc-enable.patch ];

        nativeBuildInputs = with pkgs;
          [
            (python3.withPackages (p: with p; [ setuptools pyelftools ]))

            swig
            ncurses
            gnumake
            bison
            flex
            openssl
            bc
          ] ++ [ rkbin ];

        configurePhase = ''
          make ARCH=arm evb-rk3588_defconfig
        '';

        buildPhase = ''
          patchShebangs tools scripts
          make -j$(nproc) \
            ROCKCHIP_TPL=${rkbin}/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_v1.12.bin \
            BL31=${rkbin}/rk3588_bl31_v1.40.elf
        '';

        installPhase = ''
          mkdir $out
          cp u-boot-rockchip.bin $out
        '';
      };

      rk-valhal = pkgs.runCommand "" {
        src = pkgs.fetchurl {
          url =
            "https://github.com/JeffyCN/mirrors/raw/libmali/lib/aarch64-linux-gnu/libmali-valhall-g610-g6p0-x11-wayland-gbm.so";
          sha256 = "0yzwlc1mm7adqv804jqm2ikkn1ji0pv1fpxjb9xxw69r2wbmlhkl";
        };
      } ''
        mkdir $out/lib -p
        cp $src $out/lib/libmali.so.1
        ln -s libmali.so.1 $out/lib/libmali-valhall-g610-g6p0-x11-wayland-gbm.so
        for l in libEGL.so libEGL.so.1 libgbm.so.1 libGLESv2.so libGLESv2.so.2 libOpenCL.so.1; do ln -s libmali.so.1 $out/lib/$l; done
      '';

      nixos-orangepi-5x = pkgs.stdenvNoCC.mkDerivation {
        pname = "nixos-orangepi-5x";
        version = "unstable";

        src = ./.;

        installPhase = ''
          tar czf $out *
        '';
      };

      buildConfig = { pkgs, lib, ... }: {
        boot.kernelPackages = pkgs.linuxPackagesFor
          (pkgs.callPackage ./board/kernel { src = inputs.linux-rockchip; });

        # most of required modules had been builtin
        boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" ];

        boot.initrd.includeDefaultModules =
          false; # no thanks, builtin modules should be enough

        hardware = {
          deviceTree = { name = "rockchip/rk3588s-orangepi-5b.dtb"; };

          opengl = {
            enable = true;
            package = lib.mkForce ((pkgs.mesa.override {
              galliumDrivers = [ "panfrost" "swrast" ];
              vulkanDrivers = [ "swrast" ];
            }).overrideAttrs (_: {
              pname = "mesa-panfork";
              version = "23.0.0-panfork";
              src = inputs.mesa-panfork;
            })).drivers;
            extraPackages = [ rk-valhal ];
          };

          firmware = [ (pkgs.callPackage ./board/firmware { }) ];

        };

        # ENV VARS
        environment.sessionVariables = {
          MOZ_ENABLE_WAYLAND = "1";
          TERM = "foot";
          TERMINAL = "foot";
          BROWSER = "firefox";
          VISUAL = "nvim";
        };

        # NeoVim
        programs.neovim = {
          enable = true;
          defaultEditor = true;
          configure = {
            customRC = ''
              set number
              set tabstop=2
              set shiftwidth=2
            '';
          };
        };

        # Hyprland
        programs.hyprland.enable = true;

        # fish shell
        programs.fish.enable = true;
        users.defaultUserShell = pkgs.fish;
        environment.shells = with pkgs; [ fish ];

        # Bootloader stuff
        boot.loader.grub.enable = false;
        boot.loader.generic-extlinux-compatible.enable = true;

        # Configure network proxy if necessary
        # networking.proxy.default = "http://user:password@proxy:port/";
        # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

        # Enable networking and set hostname
        networking = {
          hostName = "nixos";
          networkmanager.enable = true;
          wireless.enable = false;
        };

        # Set your time zone.
        time.timeZone = "Europe/Berlin";

        # Select internationalisation properties.
        i18n.defaultLocale = "de_DE.utf8";

        # Enable the X11 windowing system.
        services.xserver.enable = true;

        # Fonts
        fonts.packages = with pkgs; [
          noto-fonts
          noto-fonts-cjk
          noto-fonts-emoji
          liberation_ttf
          fira-code
          fira-code-symbols
          dina-font
          proggyfonts
          font-awesome
          meslo-lgs-nf
          ubuntu_font_family
          (nerdfonts.override { fonts = [ "FiraCode" "DroidSansMono" ]; })
        ];

        # Greeter
        # Run GreetD on TTY2
        services.greetd = {
          enable = true;
          vt = 7;
          settings = {
            default_session = {
              command = "${
                  lib.makeBinPath [ pkgs.greetd.tuigreet ]
                }/tuigreet --user-menu --time --cmd Hyprland";
              user = "greeter";
            };
          };
        };

        # Configure keymap in X11
        services.xserver = {
          layout = "de";
          xkbVariant = "";
        };

        # Configure console keymap
        console.keyMap = "de";

        # Enable CUPS to print documents.
        services.printing.enable = true;

        # XDG stuff
        services.dbus.enable = true;
        xdg.portal = {
          enable = true;
          extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        };

        # Enable gvfs (mount, trash...) for thunar
        services.gvfs.enable = true; # Mount, trash, and other functionalities
        services.tumbler.enable = true; # Thumbnail support for images

        nixpkgs.overlays = [
          (self: super: {
            waybar = super.waybar.overrideAttrs (oldAttrs: {
              mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
            });
          })
        ];

        # Enable sound with pipewire.
        sound.enable = true;
        hardware.pulseaudio.enable = false;
        security.rtkit.enable = true;
        services.pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
        };

        # Define a user account. Don't forget to set a password with ‘passwd’.
        users.users.cenk = {
          initialPassword = "yo";
          isNormalUser = true;
          description = "Cenk";
          extraGroups = [ "networkmanager" "wheel" "input" "tty" "video" ];
        };

        # List packages installed in system profile. To search, run:
        # $ nix search wget
        environment.systemPackages = with pkgs; [
          wget
          minizip
          git
          foot
          gnome3.adwaita-icon-theme
          waybar
          xdg-desktop-portal
          xdg-desktop-portal-hyprland
          grim
          slurp
          pipewire
          wireplumber
          pavucontrol
          xfce.thunar
          hyprpaper
          gnome.gnome-themes-extra
          imv
          rofi-wayland
          ranger
          neofetch
          mpv
          mako
          wl-clipboard
          brightnessctl
          killall
          playerctl
          #mpc-cli
          unzip
          #ffmpeg
          xarchiver
          #obs-studio
          #python3
          polkit
          polkit-kde-agent
          #chromium
        ];

        system.stateVersion = "23.05"; # Did you read the comment?

      };
    in rec {
      # to boot from SDCard
      nixosConfigurations.live = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
          (buildConfig {
            inherit pkgs;
            lib = nixpkgs.lib;
          })
          ({ pkgs, lib, ... }: {
            # all modules we need are builtin already, the nixos default profile might add
            # some which is not available, force to not use any other.
            boot.initrd.availableKernelModules = lib.mkForce [ ];

            # rockchip bootloader needs 16MiB+
            sdImage = {
              # 16MiB should be enough (u-boot-rockchip.bin ~ 10MiB)
              firmwarePartitionOffset = 16;
              firmwarePartitionName = "Firmwares";

              compressImage = true;
              expandOnBoot = true;

              # u-boot-rockchip.bin is all-in-one bootloader blob, flashing to the image should be enough
              populateFirmwareCommands =
                "dd if=${u-boot}/u-boot-rockchip.bin of=$img seek=64 conv=notrunc";

            };
          })
        ];
      };

      formatter.aarch64-linux = pkgs.nixpkgs-fmt;

      packages.aarch64-linux.default =
        nixosConfigurations.live.config.system.build.sdImage;

      #apps.aarch64-linux.default = { type = "app"; program = "${packages.aarch64-linux.sdwriter}"; };
    };
}
