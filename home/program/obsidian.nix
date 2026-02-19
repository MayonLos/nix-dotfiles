{
    pkgs,
    ...
}:

{
    programs.obsidian = {
        enable = true;
        package = pkgs.obsidian;
        vaults = {
            main = {
                enable = true;
                target = "Notes";
            };
        };
        defaultSettings = {
        };
    };
}