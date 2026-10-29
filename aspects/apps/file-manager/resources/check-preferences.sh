# Executed only on a private D-Bus session with a disposable HOME by checks.nix.
export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
seed_file="$1"
query() { xfconf-query --channel thunar "$@"; }
seed() { bash -euo pipefail "$seed_file"; }
seed
[ "$(query -p /last-menubar-visible)" = false ]
[ "$(query -p /last-location-bar)" = ThunarLocationButtons ]
[ "$(query -p /last-view)" = ThunarDetailsView ]
[ "$(query -p /last-toolbar-items)" = 'back:1,forward:1,location-bar:1,view-switcher:1,search:1,menu:0,open-parent:0,open-home:0,new-tab:0,new-window:0,toggle-split-view:0,undo:0,redo:0,zoom-out:0,zoom-in:0,zoom-reset:0,view-as-icons:0,view-as-detailed-list:0,view-as-compact-list:0,reload:0' ]

# A user's later choices and unrelated state survive every subsequent activation.
query -p /last-menubar-visible -s true
query -p /last-location-bar -s ThunarLocationEntry
query -p /last-view -s ThunarIconView
query -p /last-toolbar-items -s 'open-home:1,location-bar:1,search:0'
query -p /last-separator-position -s 247
query -p /last-details-view-visible-columns -s 'THUNAR_COLUMN_NAME,THUNAR_COLUMN_TYPE'
query -p /user-fixture -n -t string -s keep-me
before=$(query -lv)
seed
[ "$(query -lv)" = "$before" ]

# The old toolbar keys are input to upstream's own migration. Do not mask them.
query -p / -r -R
query -p /last-toolbar-item-order -n -t string -s '3,2,1,0'
query -p /last-toolbar-visible-buttons -n -t string -s '1,0,1,0'
seed
! query -p /last-toolbar-items >/dev/null 2>&1
[ "$(query -p /last-toolbar-item-order)" = '3,2,1,0' ]
[ "$(query -p /last-toolbar-visible-buttons)" = '1,0,1,0' ]
[ "$(query -p /last-menubar-visible)" = false ]
