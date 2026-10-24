_:
let
  mkAvatar =
    pkgs: palette:
    pkgs.runCommand "mayon-avatar.png"
      {
        nativeBuildInputs = [ pkgs.librsvg ];
        FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.inter ]; };
      }
      ''
        cat > avatar.svg <<'SVG'
        <svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
          <rect width="512" height="512" rx="112" fill="${palette.blue}"/>
          <text x="256" y="272" text-anchor="middle" dominant-baseline="central"
            fill="${palette.black}" font-family="${palette.fonts.sans}" font-size="328" font-weight="700">M</text>
        </svg>
        SVG
        rsvg-convert --width 512 --height 512 --output "$out" avatar.svg
      '';
in
{
  den.aspects."mayon@nixos-btw" =
    { user, ... }:
    {
      user = { pkgs, ... }: {
        isNormalUser = true;
        home = "/home/mayon";
        extraGroups = [
          "wheel"
          "networkmanager"
        ];
        packages = [ pkgs.tree ];
      };
      homeManager =
        {
          config,
          hostFacts,
          lib,
          pkgs,
          ...
        }:
        let
          avatar = mkAvatar pkgs user.appearance;
          faceSource = "${config.xdg.dataHome}/nix-dotfiles/mayon-avatar.png";
        in
        {
          programs.zsh.initContent = lib.mkBefore ''
            for _s in deepseek-api-key:DEEPSEEK_API_KEY; do
              _file="/run/secrets/''${_s%%:*}"
              _var="''${_s##*:}"
              [ -r "$_file" ] && export "$_var=$(<"$_file")"
            done
            unset _s _file _var

          '';
          home = {
            username = "mayon";
            homeDirectory = "/home/mayon";
            stateVersion = "25.11";
          };

          # Use a stable managed target: future generations refresh the PNG
          # without guessing ownership from an existing file's store basename.
          xdg.dataFile."nix-dotfiles/mayon-avatar.png".source = avatar;
          home.activation.seedMayonAvatar = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            face="$HOME/.face"
            if [ ! -e "$face" ] && [ ! -L "$face" ]; then
              run ln -s ${lib.escapeShellArg faceSource} "$face"
            fi
          '';

          # The locked login box has no profile image. Its native sticker
          # widget can display the user-owned .face without an upstream patch.
          programs.noctalia.settings.lockscreen_widgets = lib.mkIf config.programs.noctalia.enable {
            widget_order = lib.mkAfter [ "lockscreen-widget-avatar" ];
            widget.lockscreen-widget-avatar = {
              type = "sticker";
              output = hostFacts.display.name;
              cx = hostFacts.display.width / hostFacts.display.scale / 2;
              # Above the clock, leaving the login panel's auth card clear.
              cy = hostFacts.display.height / hostFacts.display.scale * 0.13;
              box_width = 80.0;
              box_height = 80.0;
              settings = {
                image_path = "${config.home.homeDirectory}/.face";
                opacity = 1.0;
              };
            };
          };
        };
    };

  # AccountsService cache belongs to the host, so install its avatar through
  # the host aspect rather than relying on a user's un-routed NixOS class.
  den.aspects.nixos-btw =
    { host, ... }:
    {
      nixos =
        { lib, pkgs, ... }:
        let
          avatar = mkAvatar pkgs host.appearance;
          iconFile = "/var/lib/AccountsService/icons/mayon";
          usersFile = "/var/lib/AccountsService/users/mayon";
        in
        {
          environment.etc."nix-dotfiles/mayon-avatar.png".source = avatar;
          system.activationScripts.mayonAccountsServiceAvatar = {
            deps = [
              "users"
              "etc"
            ];
            text = ''
              icon_file=${lib.escapeShellArg iconFile}
              users_file=${lib.escapeShellArg usersFile}
              avatar=/etc/nix-dotfiles/mayon-avatar.png
              icon_dir="$(dirname "$icon_file")"
              users_dir="$(dirname "$users_file")"

              # Refuse to follow administrator-managed directory symlinks.
              if [ ! -L /var/lib/AccountsService ] && [ ! -L "$icon_dir" ] && [ ! -L "$users_dir" ]; then
                mkdir -p "$icon_dir" "$users_dir"

                if [ ! -e "$icon_file" ] && [ ! -L "$icon_file" ]; then
                  ln -s "$avatar" "$icon_file"
                fi

                if [ -L "$users_file" ]; then
                  # Do not replace a symlink or write through it.
                  :
                elif [ ! -e "$users_file" ]; then
                  printf '[User]\nIcon=%s\n' "$icon_file" > "$users_file"
                  chmod 0644 "$users_file"
                elif [ -f "$users_file" ]; then
                  temp_file="$(mktemp "$users_dir/.mayon.XXXXXX")"
                  # GKeyFile allows whitespace around keys. Inspect the User
                  # section first; preserve every nonempty custom Icon value.
                  ${pkgs.gawk}/bin/awk -v icon="$icon_file" '
                    function section(line) {
                      sub(/^[[:space:]]*\[/, "", line)
                      sub(/\][[:space:]]*$/, "", line)
                      return line
                    }
                    FNR == NR {
                      if ($0 ~ /^[[:space:]]*\[[^]]+\][[:space:]]*$/) current = section($0)
                      if (current == "User" && $0 ~ /^[[:space:]]*Icon[[:space:]]*=/) {
                        hasIcon = 1
                        value = $0
                        sub(/^[^=]*=[[:space:]]*/, "", value)
                        if (value ~ /[^[:space:]]/) { customIcon = 1; exit }
                      }
                      next
                    }
                    {
                      if ($0 ~ /^[[:space:]]*\[[^]]+\][[:space:]]*$/) {
                        currentOut = section($0)
                        if (currentOut == "User") {
                          print
                          if (!userSeen && !hasIcon) print "Icon=" icon
                          userSeen = 1
                          next
                        }
                      }
                      if (!customIcon && currentOut == "User" && $0 ~ /^[[:space:]]*Icon[[:space:]]*=/) {
                        print "Icon=" icon
                      } else print
                    }
                    END { if (!customIcon && !userSeen) { print ""; print "[User]"; print "Icon=" icon } }
                  ' "$users_file" "$users_file" > "$temp_file"
                  if [ ! -s "$temp_file" ] || cmp -s "$users_file" "$temp_file"; then
                    rm "$temp_file"
                  else
                    chmod --reference="$users_file" "$temp_file"
                    chown --reference="$users_file" "$temp_file"
                    mv "$temp_file" "$users_file"
                  fi
                fi
              fi
            '';
          };
        };
    };
}
