{ pkgs }:
pkgs.writeShellApplication {
  name = "legion-conservation";
  text = ''
    shopt -s nullglob
    nodes=(/sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode)
    if (( ''${#nodes[@]} == 0 )) && [[ "''${1:-status}" == status ]]; then
      exit 0
    fi
    if (( ''${#nodes[@]} != 1 )); then
      echo 'Expected one ideapad conservation_mode attribute' >&2
      exit 1
    fi
    node="''${nodes[0]}"
    value=$(<"$node")
    case "$value" in
      0|1) ;;
      *) echo 'Invalid conservation_mode value' >&2; exit 1 ;;
    esac
    case "''${1:-status}" in
      status) [[ "$value" == 0 ]] || printf '养护\n' ;;
      toggle) printf '%s\n' "$((1 - value))" > "$node" ;;
      *) echo 'Usage: legion-conservation [status|toggle]' >&2; exit 2 ;;
    esac
  '';
}
