# Claude Code status line. Reads the session JSON on stdin and prints one
# line that follows the Starship prompt in aspects/command-line/zsh.nix:
#
#   nix-dotfiles/aspects  main ↑1 +2 ~3 ?1  ❄ cuda │ Opus 5.5 high │ ctx 42% │ 5h 18% │ +120 −8
#
# Optional segments appear only when their field is present or non-zero.
# Field names follow Claude Code's status line payload (checked against the
# 2.1.299 bundle); missing fields fall back to empty instead of failing.

input=$(cat)

# One jq pass; fields are separated by the ASCII unit separator so empty
# values keep their position.
IFS=$'\x1f' read -r cwd project model effort fast ctx five seven added removed pr vim agent < <(
  jq -r '[
    (.workspace.current_dir // .cwd // ""),
    (.workspace.project_dir // ""),
    (.model.display_name // ""),
    (.effort.level // ""),
    (.fast_mode // false),
    (.context_window.used_percentage // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.pr.number // ""),
    (.vim.mode // ""),
    (.agent.name // "")
  ] | map(tostring) | join("\u001f")' <<<"$input" 2>/dev/null
) || true
cwd=${cwd:-$PWD}

reset=$'\e[0m' bold=$'\e[1m' dim=$'\e[2m'
cyan=$'\e[36m' blue=$'\e[34m' purple=$'\e[35m' yellow=$'\e[33m'
green=$'\e[32m' red=$'\e[31m'
sep=" ${dim}│${reset} "

# Green below 50%, yellow below 80%, red from 80%.
level_color() {
  local n=${1%%.*}
  if ((n >= 80)); then
    printf '%s' "$red"
  elif ((n >= 50)); then
    printf '%s' "$yellow"
  else
    printf '%s' "$green"
  fi
}

out=""

# Starship only shows user@host for root or SSH sessions; do the same.
if [[ -n ${SSH_CONNECTION:-} || $EUID -eq 0 ]]; then
  user_color=$cyan
  ((EUID == 0)) && user_color=$red
  out+="${bold}${user_color}$(id -un)${reset}@${bold}${cyan}$(hostname -s)${reset} "
fi

# Directory: relative to the repository root like Starship's
# truncate_to_repo, otherwise ~-relative; keep the last three components.
top=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null) || top=""
if [[ -n $top ]]; then
  dir="${top##*/}${cwd#"$top"}"
else
  dir=${cwd/#"$HOME"/\~}
fi
IFS=/ read -ra parts <<<"$dir"
if ((${#parts[@]} > 3)); then
  dir="…/$(
    IFS=/
    echo "${parts[*]: -3}"
  )"
fi
out+="${bold}${blue}${dir}${reset}"

# Git: one porcelain v2 call for branch, ahead/behind and change counts.
if [[ -n $top ]]; then
  branch="" oid="" ahead=0 behind=0 staged=0 changed=0 untracked=0 conflicts=0
  while IFS= read -r line; do
    case $line in
    "# branch.head "*) branch=${line#\# branch.head } ;;
    "# branch.oid "*) oid=${line#\# branch.oid } ;;
    "# branch.ab "*)
      read -r _ _ a b <<<"$line"
      ahead=${a#+} behind=${b#-}
      ;;
    "? "*) untracked=$((untracked + 1)) ;;
    "u "*) conflicts=$((conflicts + 1)) ;;
    [12]" "*)
      xy=${line:2:2}
      [[ ${xy:0:1} != . ]] && staged=$((staged + 1))
      [[ ${xy:1:1} != . ]] && changed=$((changed + 1))
      ;;
    esac
  done < <(git -C "$cwd" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)
  [[ $branch == "(detached)" ]] && branch=${oid:0:7}

  status=""
  ((ahead)) && status+=" ↑$ahead"
  ((behind)) && status+=" ↓$behind"
  ((conflicts)) && status+=" ${red}=$conflicts${yellow}"
  ((staged)) && status+=" +$staged"
  ((changed)) && status+=" ~$changed"
  ((untracked)) && status+=" ?$untracked"
  out+="  ${bold}${purple} ${branch}${reset}${yellow}${status}${reset}"
fi

# Dev shells: `nix develop .#cuda` exports name=cuda; plain shells use nix-shell.
if [[ -n ${IN_NIX_SHELL:-} ]]; then
  shell_name=${name:-}
  [[ $shell_name == nix-shell ]] && shell_name=""
  out+="  ${cyan}❄${shell_name:+ $shell_name}${reset}"
fi

# A subdirectory launch is worth flagging when Claude moved away from it.
if [[ -n $project && $project != "$cwd" && -z $top ]]; then
  out+=" ${dim}(${project/#"$HOME"/\~})${reset}"
fi

if [[ -n $model ]]; then
  seg="$model"
  [[ -n $effort ]] && seg+=" ${dim}${effort}${reset}"
  [[ $fast == true ]] && seg+=" ${yellow}↯${reset}"
  out+="${sep}${seg}"
fi

[[ -n $agent ]] && out+="${sep}${cyan}@${agent}${reset}"

if [[ -n $ctx ]]; then
  out+="${sep}ctx $(level_color "$ctx")$(printf '%.0f' "$ctx")%${reset}"
fi

if [[ -n $five ]]; then
  out+="${sep}5h $(level_color "$five")$(printf '%.0f' "$five")%${reset}"
fi
# The weekly window only matters once it starts to constrain usage.
if [[ -n $seven && ${seven%%.*} -ge 50 ]]; then
  out+=" ${dim}7d${reset} $(level_color "$seven")$(printf '%.0f' "$seven")%${reset}"
fi

if ((added || removed)); then
  out+="${sep}${green}+${added}${reset} ${red}−${removed}${reset}"
fi

[[ -n $pr ]] && out+="${sep}${purple}PR #${pr}${reset}"
[[ -n $vim ]] && out+="${sep}${dim}${vim}${reset}"

printf '%s\n' "$out"
