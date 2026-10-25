"""Parse a rendered stylesheet with the real GTK provider, without a display."""
import sys
import gi

gi.require_version("Gtk", sys.argv[1])
from gi.repository import Gtk  # noqa: E402

errors = []
provider = Gtk.CssProvider()
provider.connect("parsing-error", lambda _provider, _section, error: errors.append(str(error)))
provider.load_from_path(sys.argv[2])
if errors:
    raise SystemExit("\n".join(errors))
