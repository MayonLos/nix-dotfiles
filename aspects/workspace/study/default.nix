_: {
  den.aspects.study.homeManager =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.studyMayon ];
      xdg.configFile."study/reminders-enabled".text = "${pkgs.studyMayon}/bin/study-mayon\n";
      xdg.desktopEntries.study-mayon = {
        name = "学习";
        comment = "FSRS 背单词与大学课表";
        exec = "${pkgs.kitty}/bin/kitty --class study-mayon --title 学习 -e ${pkgs.studyMayon}/bin/study-mayon";
        icon = "accessories-dictionary";
        terminal = false;
        categories = [ "Education" ];
      };
      # One short bootstrap per login/day. The program arms only the next exact
      # deadline as a transient timer; no minute polling or resident process.
      systemd.user.services.study-plan = {
        Unit.Description = "Schedule the next Study notification";
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.studyMayon}/bin/study-mayon remind";
          UMask = "0077";
        };
      };
      systemd.user.timers.study-plan = {
        Unit.Description = "Study reminder bootstrap";
        Timer = {
          OnStartupSec = "2min";
          OnCalendar = "*-*-* 00:00:05";
          Persistent = true;
          AccuracySec = "30s";
          Unit = "study-plan.service";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
}
