{ host }:
{
  lib,
  pkgs,
  ...
}:
let
  avatar = import ./package.nix {
    inherit pkgs;
    name = host.avatar.name;
    initial = host.avatar.initial;
    palette = host.appearance;
  };
  iconFile = "/var/lib/AccountsService/icons/${host.avatar.name}";
  usersFile = "/var/lib/AccountsService/users/${host.avatar.name}";
in
{
  environment.etc."nix-dotfiles/${host.avatar.name}-avatar.png".source = avatar;
  system.activationScripts.mayonAccountsServiceAvatar = {
    deps = [
      "users"
      "etc"
    ];
    text = ''
      icon_file=${lib.escapeShellArg iconFile}
      users_file=${lib.escapeShellArg usersFile}
      avatar=/etc/nix-dotfiles/${host.avatar.name}-avatar.png
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
          temp_file="$(mktemp "$users_dir/.${host.avatar.name}.XXXXXX")"
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
}
