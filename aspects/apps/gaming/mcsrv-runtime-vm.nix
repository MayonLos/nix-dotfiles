{ pkgs }:
let
  jdk = pkgs.javaPackages.compiler.temurin-bin.jdk-21;
  lanClass = pkgs.runCommand "mcsrv-test-lan-client" { nativeBuildInputs = [ jdk ]; } ''
    mkdir -p "$out"
    cat > EntryPoint.java <<'JAVA'
    package org.prismlauncher;
    public class EntryPoint {
      public static void main(String[] args) throws Exception {
        var socket = new java.net.ServerSocket(50000);
        while (true) {
          try (var peer = socket.accept()) {
            var bytes = peer.getInputStream().readNBytes(4);
            peer.getOutputStream().write(bytes);
          }
        }
      }
    }
    JAVA
    javac -d "$out" EntryPoint.java
  '';
  # A synthetic server exercises transport/ownership without downloading Minecraft
  # or touching a Prism instance. It implements stdin stop and an actual TCP echo.
  listener = pkgs.writeText "mcsrv-test-listener.py" ''
    import os, socket, sys, threading
    if '-version' in sys.argv:
        print('openjdk version "21.0.1"', file=sys.stderr)
        sys.exit(0)
    port = int(next((x.split('=')[1] for x in open('server.properties') if x.startswith('server-port=')), '25565'))
    os.makedirs('world', exist_ok=True)
    open('world/sentinel', 'w').write('isolated-world')
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', port))
    server.listen()
    def serve():
        while True:
            conn, _ = server.accept()
            with conn:
                data = conn.recv(4096)
                conn.sendall(data)
    threading.Thread(target=serve, daemon=True).start()
    print('Done (0.1s)!', flush=True)
    for line in sys.stdin:
        if line.strip() == 'stop': sys.exit(0)
        print('console: '+line.strip(), flush=True)
  '';
  java = pkgs.writeShellScript "mcsrv-test-java" ''
    exec ${pkgs.python3}/bin/python3 -u ${listener} "$@"
  '';
  common = {
    # force: the test harness also assigns pkgs; reuse the already overlaid package set.
    nixpkgs.pkgs = pkgs.lib.mkForce pkgs;
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
      linger = true;
    };
    environment.systemPackages = [
      pkgs.mcsrvMayon
      pkgs.frp
      pkgs.openssh
      pkgs.rsync
      pkgs.tmux
      pkgs.python3
    ];
    virtualisation.memorySize = 1024;
  };
in
pkgs.testers.runNixOSTest {
  name = "mcsrv-network-runtime";
  nodes = {
    cloud = { ... }: {
      imports = [ common ];
      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
      };
      networking.firewall.allowedTCPPorts = [
        25565
        17000
        25570
      ];
    };
    client = { ... }: {
      imports = [
        common
        ./host/mcsrv-firewall.nix
      ];
      users.users.alice.extraGroups = [ "mcsrv-firewall" ];
    };
  };
  testScript = ''
    import json, shlex
    start_all()
    for machine in (client, cloud):
        machine.wait_for_unit('multi-user.target')
        machine.wait_for_unit('user@1000.service')
    def user(machine, command):
        return machine.succeed('runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1000 '+command)
    def cli(command):
        return user(client, 'mcsrv-mayon --root /home/alice/mc '+command)
    client.succeed('install -d -m 700 -o alice -g users /home/alice/.ssh')
    user(client, 'ssh-keygen -q -t ed25519 -N "" -f /home/alice/.ssh/id_ed25519')
    pub = client.succeed('cat /home/alice/.ssh/id_ed25519.pub').strip()
    cloud.succeed('install -d -m 700 -o alice -g users /home/alice/.ssh')
    cloud.succeed('echo '+shlex.quote(pub)+' > /home/alice/.ssh/authorized_keys; chown alice:users /home/alice/.ssh/authorized_keys; chmod 600 /home/alice/.ssh/authorized_keys')
    known = user(client, 'ssh-keyscan cloud')
    client.succeed('echo '+shlex.quote(known)+' > /home/alice/.ssh/known_hosts; chown alice:users /home/alice/.ssh/known_hosts; chmod 600 /home/alice/.ssh/known_hosts')
    # Only VM-generated credentials are involved. No host SSH configuration is mounted.
    cli('target add test alice@cloud --java ${java}')
    config = dict(name='friends', kind='vanilla', version='1.21.1', memory_mb=1024,
                  port=25565, online_mode=True, whitelist=True, java='${java}',
                  argv=[], backup_minutes=0, keep_last=20, lan=False, aikar=False,
                  rcon=False, bind="")
    client.succeed('install -d -m 700 -o alice -g users /home/alice/mc/friends')
    def write(machine,path,content):
        machine.succeed('printf %s '+shlex.quote(content)+' > '+shlex.quote(path)+'; chown alice:users '+shlex.quote(path)+'; chmod 600 '+shlex.quote(path))
    write(client,'/home/alice/mc/friends/instance.json',json.dumps(config))
    write(client,'/home/alice/mc/friends/server.properties','server-port=25565\nlevel-name=world\n')
    write(client,'/home/alice/mc/friends/installed.json','{"loader":"vanilla"}')
    write(client,'/home/alice/mc/friends/rcon.secret','fixture-only')
    cli('cloud test deploy friends --confirm friends')
    cli('cloud test start friends')
    cloud.wait_for_open_port(25565)
    echo = "import socket; s=socket.create_connection(('cloud',25565)); s.sendall(b'direct-cloud'); assert s.recv(128)==b'direct-cloud'"
    client.succeed('python3 -c '+shlex.quote(echo))
    assert '运行中' in cli('cloud test status friends')
    cli('cloud test command friends '+shlex.quote("say ' $(touch /home/alice/INJECTION) `id`;"))
    cloud.fail('test -e /home/alice/INJECTION')
    cli('cloud test stop friends')
    cloud.wait_for_closed_port(25565)
    cli('cloud test backup friends')
    client.succeed('tar -tzf /home/alice/mc/cloud-backups/test/*.tar.gz | grep world/sentinel')
    # Independent local-server frp tunnel: cloud is only the relay here.
    # Provision the optional relay through the tool; its token is generated at
    # VM runtime, written 0600, and sent to ssh stdin rather than argv/Nix strings.
    cli('frp relay test --confirm test --bind-port 17000 --allow-start 25570 --allow-end 25570')
    cloud.wait_for_open_port(17000)
    client.succeed('test "$(stat -c %a /home/alice/mc/frps-secrets/test.token)" = 600')
    cli('frp set friends --server cloud --server-port 17000 --remote-port 25570 --token-file /home/alice/mc/frps-secrets/test.token')
    cli('start friends')
    client.wait_for_open_port(25565)
    cloud.wait_for_open_port(25570)
    echo = "import socket; s=socket.create_connection(('cloud',25570)); s.sendall(b'frp-tunnel'); assert s.recv(128)==b'frp-tunnel'"
    client.succeed('python3 -c '+shlex.quote(echo))
    # Assert neither argv nor manager/Java logs contain the runtime secret.
    audit = "import glob; t=open('/home/alice/mc/frps-secrets/test.token','rb').read()\nfor p in glob.glob('/proc/[0-9]*/cmdline'):\n try:\n  assert t not in open(p,'rb').read()\n except (FileNotFoundError,ProcessLookupError): pass\nassert t not in open('/home/alice/mc/friends/console.log','rb').read()"
    client.succeed('python3 -c '+shlex.quote(audit))
    cli('stop friends')
    client.wait_for_closed_port(25565)
    cloud.wait_for_closed_port(25570)
    client.succeed('systemctl start mcsrv-lan@1000_1_1_22.service || true')
    client.wait_until_fails('systemctl is-active --quiet mcsrv-lan@1000_1_1_22.service')
    client.fail('iptables -S nixos-fw | grep mcsrv-mayon-lan')
    # Real packaged Java, synthetic Prism client: prove root validation and cleanup.
    cwd = '/home/alice/.local/share/PrismLauncher/instances/fixture/.minecraft'
    client.succeed('install -d -m 700 -o alice -g users '+cwd)
    user(client, 'systemd-run --user --unit=fixture-lan-java --working-directory='+cwd+' ${jdk}/bin/java -cp ${lanClass} org.prismlauncher.EntryPoint')
    client.wait_for_open_port(50000)
    worlds = json.loads(cli('lan list'))
    if not worlds:
        pid = user(client,'systemctl --user show -p MainPID --value fixture-lan-java.service').strip()
        ticks = client.succeed('cut -d " " -f 22 /proc/'+pid+'/stat').strip()
        print(client.execute('mcsrv-mayon lan-validate 1000_'+pid+'_'+ticks+'_50000'))
    assert len(worlds)==1 and worlds[0]['port']==50000
    check = "import socket; s=socket.create_connection(('client',50000),timeout=2)"
    cloud.fail('python3 -c '+shlex.quote(check))
    cli('frp set lan --server cloud --server-port 17000 --remote-port 25570 --token-file /home/alice/mc/frps-secrets/test.token')
    user(client,'systemd-run --user --unit=fixture-lan-share mcsrv-mayon --root /home/alice/mc lan share --seconds 120')
    cloud.wait_until_succeeds('python3 -c '+shlex.quote(check))
    cloud.wait_for_open_port(25570)
    echo = "import socket; s=socket.create_connection(('cloud',25570)); s.sendall(b'lan!'); assert s.recv(4)==b'lan!'"
    cloud.succeed('python3 -c '+shlex.quote(echo))
    # An unverified request cannot revoke another full-id lease on the same port.
    client.succeed('systemctl start mcsrv-lan@1000_1_1_50000.service || true')
    client.wait_until_fails('systemctl is-active --quiet mcsrv-lan@1000_1_1_50000.service')
    cloud.succeed('python3 -c '+shlex.quote(check))
    user(client,'systemctl --user stop fixture-lan-java.service')
    client.wait_until_fails('iptables -S nixos-fw | grep mcsrv-mayon-lan')
    cloud.wait_for_closed_port(25570)
    client.wait_until_fails('runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user is-active --quiet fixture-lan-share.service')
    # Expiration also withdraws the lease while the game is still listening.
    cli('frp off lan')
    user(client, 'systemd-run --user --unit=fixture-lan-java2 --working-directory='+cwd+' ${jdk}/bin/java -cp ${lanClass} org.prismlauncher.EntryPoint')
    client.wait_for_open_port(50000)
    user(client,'systemd-run --user --unit=fixture-lan-expiry mcsrv-mayon --root /home/alice/mc lan share --seconds 5')
    cloud.wait_until_succeeds('python3 -c '+shlex.quote(check))
    client.wait_until_fails('iptables -S nixos-fw | grep mcsrv-mayon-lan')
    cloud.fail('python3 -c '+shlex.quote(check))
    client.succeed('runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user is-active --quiet fixture-lan-java2.service')
    user(client,'systemctl --user stop fixture-lan-java2.service')
    cli('frp relay-stop test')
    cloud.wait_for_closed_port(17000)
  '';
}
