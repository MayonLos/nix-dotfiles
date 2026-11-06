{ lib, ... }:
let
  inherit (lib) types;

  runtimeFile = types.addCheck types.str (
    value: lib.hasPrefix "/" value && !(lib.hasPrefix "/nix/store/" value)
  );

  proxy = types.submodule {
    options = {
      localPort = lib.mkOption {
        type = types.port;
        description = "Port of the local service, reached on 127.0.0.1.";
      };
      remotePort = lib.mkOption {
        type = types.port;
        description = "Public port on the relay; the relay's allowPorts must include it.";
      };
      protocol = lib.mkOption {
        type = types.enum [
          "tcp"
          "udp"
        ];
        default = "tcp";
      };
    };
  };
in
{
  options.gameTunnel = lib.mkOption {
    type = types.nullOr (
      types.submodule {
        options = {
          server = lib.mkOption {
            type = types.nonEmptyStr;
            description = "Public address of the frp relay (frps).";
          };
          serverPort = lib.mkOption {
            type = types.port;
            default = 7000;
          };
          tokenFile = lib.mkOption {
            type = runtimeFile;
            description = "Runtime file holding the shared token (a sops secret). Never a store path.";
          };
          proxies = lib.mkOption {
            type = types.attrsOf proxy;
            description = "Local services to publish through the relay, by name.";
          };
        };
      }
    );
    default = null;
    description = "On-demand frp client that publishes local game servers through a public relay.";
  };
}
