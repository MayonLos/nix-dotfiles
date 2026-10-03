# systemd user unit for a process that lives with the Wayland session.
# Consumers pass only the description and the Service section; Unit/Install
# stay identical. Pure data -- no module arguments needed.
{
  description,
  service,
  wantedBy ? [ "graphical-session.target" ],
}:
{
  Unit = {
    Description = description;
    PartOf = [ "graphical-session.target" ];
    After = [ "graphical-session.target" ];
  };

  Service = service;

  Install.WantedBy = wantedBy;
}
