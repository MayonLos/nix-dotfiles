# systemd user unit for a process that lives with the Wayland session.
# Consumers pass only the description and the Service section; Unit/Install
# stay identical. Pure data -- no module arguments needed.
{
  description,
  service,
  target,
  unit ? { },
}:
let
  targets = if builtins.isList target then target else [ target ];
in
{
  Unit = {
    Description = description;
    PartOf = targets;
    After = targets;
  }
  // unit;

  Service = service;

  Install.WantedBy = targets;
}
