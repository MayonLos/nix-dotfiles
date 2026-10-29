# Query the running writer rather than editing its XML behind its back. A failed
# channel read is fatal; it must not be mistaken for a set of missing settings.
properties=$(xfconf-query --channel thunar --list)
seed() {
  local key="$1" type="$2" value="$3"
  if ! printf '%s\n' "$properties" | grep -qxF -- "$key"; then
    xfconf-query --channel thunar --property "$key" --create --type "$type" --set "$value"
  fi
}

seed /last-menubar-visible bool false
seed /last-location-bar string ThunarLocationButtons
seed /last-view string ThunarDetailsView
seed /last-separator-position int 190
seed /last-details-view-visible-columns string THUNAR_COLUMN_NAME,THUNAR_COLUMN_DATE_MODIFIED,THUNAR_COLUMN_SIZE
seed /last-details-view-column-order string THUNAR_COLUMN_NAME,THUNAR_COLUMN_DATE_MODIFIED,THUNAR_COLUMN_SIZE,THUNAR_COLUMN_TYPE,THUNAR_COLUMN_SIZE_IN_BYTES
seed /misc-symbolic-icons-in-toolbar bool true
seed /misc-small-toolbar-icons bool true

# Let upstream migrate a user's old toolbar layout; seeding the new key would
# short-circuit that migration. Unmentioned UCA buttons stay hidden upstream.
if ! printf '%s\n' "$properties" | grep -qxF /last-toolbar-item-order &&
   ! printf '%s\n' "$properties" | grep -qxF /last-toolbar-visible-buttons; then
  seed /last-toolbar-items string 'back:1,forward:1,location-bar:1,view-switcher:1,search:1,menu:0,open-parent:0,open-home:0,new-tab:0,new-window:0,toggle-split-view:0,undo:0,redo:0,zoom-out:0,zoom-in:0,zoom-reset:0,view-as-icons:0,view-as-detailed-list:0,view-as-compact-list:0,reload:0'
fi
