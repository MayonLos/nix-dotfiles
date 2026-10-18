# systemd user unit for a process that lives with the Wayland session.
# Consumers pass only the description and the Service section; Unit/Install
# stay identical. Pure data -- no module arguments needed.
{
  description,
  service,
  target,
  unit ? { },
}:
{
  Unit = {
    Description = description;
    PartOf = [ target ];
    After = [ target ];
  }
  // unit;

  Service = service;

  Install.WantedBy = [ target ];
}
