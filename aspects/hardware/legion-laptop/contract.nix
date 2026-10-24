{ lib, ... }:
{
  options.facts = lib.mkOption {
    description = "Hardware facts supplied by inventory; selecting facts enables no drivers.";
    default = { };
    type = lib.types.submodule {
      options = {
        system = lib.mkOption {
          type = lib.types.str;
          default = "x86_64-linux";
        };
        gpu = lib.mkOption {
          default = { };
          type = lib.types.submodule {
            options = {
              mpvHwdec = lib.mkOption {
                type = lib.types.str;
                default = "nvdec-copy";
              };
              gameModeDevice = lib.mkOption {
                type = lib.types.int;
                default = 0;
              };
              intelBusId = lib.mkOption {
                type = lib.types.str;
                default = "";
              };
              nvidiaBusId = lib.mkOption {
                type = lib.types.str;
                default = "";
              };
            };
          };
        };
        display = lib.mkOption {
          default = { };
          type = lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                default = "";
              };
              scale = lib.mkOption {
                type = lib.types.number;
                default = 1;
              };
              width = lib.mkOption {
                type = lib.types.int;
                default = 1920;
              };
              height = lib.mkOption {
                type = lib.types.int;
                default = 1080;
              };
              refresh = lib.mkOption {
                type = lib.types.number;
                default = 60;
              };
              x11Dpi = lib.mkOption {
                type = lib.types.int;
                default = 96;
              };
            };
          };
        };
      };
    };
  };
}
