{
  pkgs,
  ...
}:

{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    host = "127.0.0.1";
    port = 11434;
    openFirewall = false;
    syncModels = false;
    loadModels = [ ];
  };

  systemd.services.ollama.serviceConfig.SupplementaryGroups = [
    "render"
    "video"
  ];
}
