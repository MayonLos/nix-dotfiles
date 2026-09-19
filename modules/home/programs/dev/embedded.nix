{ pkgs, lib, ... }:

{
  # STM32 / Cortex-M development. Per the dev-toolchain skill's split, this is a
  # per-language module: it carries the things that *build and run* firmware.
  # The editor side (clangd, clang-format) is already in toolchain.nix and works
  # on firmware sources unchanged, because clangd reads a compile_commands.json
  # rather than a toolchain.
  #
  # cmake, ninja, pkg-config and host gdb are NOT here -- llvm.nix already
  # installs them, and a second copy would be the exact redundancy this repo
  # keeps auditing out.
  home.packages = with pkgs; [
    # The cross compiler, as ARM ships it: arm-none-eabi-{gcc,g++,objcopy,size,
    # gdb,...}. Not `pkgsCross.arm-embedded`, which would build the whole
    # toolchain locally; this one substitutes from cache.
    #
    # It brings its own arm-none-eabi-gdb, which is the one to point at
    # OpenOCD's :3333 -- the host `gdb` from llvm.nix cannot debug a Cortex-M.
    #
    # `lowPrio` because it collides with that host gdb on 78 paths:
    # include/gdb/jit-reader.h and the whole share/gdb/python/gdb tree, which
    # both packages install at the same names. Without it `home-manager-path`
    # fails to build outright ("two given paths contain a conflicting
    # subpath"). Letting the host gdb win costs nothing: both binaries resolve
    # their data directory by absolute store path, not through the profile --
    # verified with `show data-directory` on each. Nothing collides in bin/;
    # every ARM binary carries the arm-none-eabi- prefix.
    (lib.lowPrio gcc-arm-embedded)

    # Flashing and on-chip debugging, in order of how much they hide from you:
    #
    #   openocd     the general one. `openocd -f interface/stlink.cfg
    #               -f target/stm32f4x.cfg` opens a GDB server on :3333 and a
    #               telnet monitor on :4444. Works with ST-Link, DAPLink,
    #               J-Link and CMSIS-DAP; its scripts live in
    #               ${openocd}/share/openocd/scripts.
    #   stlink      st-flash / st-info / st-util, ST-Link only, no config files.
    #               `st-flash write firmware.bin 0x8000000` is the shortest
    #               path from a build to a running board.
    #   probe-rs    the modern one. `cargo-embed`-style flashing plus RTT, and
    #               it knows chips by name rather than by script path
    #               (`probe-rs run --chip STM32F411RETx`).
    openocd
    stlink
    probe-rs-tools

    # Bootloader paths that need no debug probe at all: DFU over USB (the
    # BOOT0-pin route on most STM32s) and the UART bootloader.
    dfu-util
    stm32flash

    # ST's clock/pinout configurator and HAL code generator. Unfree, hence the
    # allowUnfree already set on this flake's pkgs. It writes a project into a
    # directory you choose; keep the generated tree in the project repo, not
    # here.
    stm32cubemx

    # Serial console for the board's UART. tio over minicom/picocom: it
    # reconnects when the adapter is re-enumerated, which is what happens on
    # every reset of a board whose USB-serial is on the same chip.
    tio
  ];

  # Per-project builds should go through direnv (`use flake` in the project's
  # own .envrc, see direnv.nix) rather than growing this list. A firmware repo
  # that pins its own arm-none-eabi version is the normal case, and the point of
  # the packages above is to have a working toolchain before that pin exists.
}
