start_all()
machine.wait_for_unit("multi-user.target")
machine.wait_for_unit("polkit.service")
machine.wait_for_open_port(18080)
machine.succeed("test $(systemctl show -p ActiveState --value mayon-clash.service) = inactive")
machine.succeed("test ! -d /run/mayon-clash")

def user(command):
    return "runuser -u trial -- env HOME=/home/trial " + command

# Polkit must work over the real system bus without a password or auth agent.
machine.fail(user("systemctl --no-ask-password start unrelated.service"))
machine.fail(user("systemctl --no-ask-password start mayon-clash.service"))
machine.wait_until_succeeds("journalctl -u mayon-clash.service --no-pager -o cat | grep '配置目录不存在'")
machine.succeed("systemctl reset-failed mayon-clash.service")
machine.succeed(user("sh -c 'printf http://127.0.0.1:18080/sub | clashtui-mayon profile add'"))
machine.succeed(user("clashtui-mayon profile list | grep 'VM trial'"))
machine.succeed("test $(stat -c %a /home/trial/.local/share/mayon-clash) = 700")
machine.succeed("test $(stat -c %a /home/trial/.local/share/mayon-clash/subscriptions.toml) = 600")
machine.wait_for_unit("network-online.target")
machine.succeed("ip -j route show table all > /tmp/routes-before.json")
machine.succeed("ip -j rule show > /tmp/rules-before.json")
machine.succeed(user("systemctl --no-ask-password start mayon-clash.service"))
machine.wait_for_unit("mayon-clash.service")
machine.wait_until_succeeds("ip link show mayon-clash")
machine.wait_until_succeeds("curl --fail --unix-socket /run/mayon-clash/mihomo.sock http://localhost/version")
machine.succeed("test $(stat -c %a /run/mayon-clash) = 700")
machine.succeed("test $(stat -c %a /home/trial/.local/share/mayon-clash/GeoIP.dat) = 600")
machine.succeed("test $(stat -c %a /home/trial/.local/share/mayon-clash/GeoSite.dat) = 600")
machine.succeed("test $(stat -c %a /home/trial/.local/share/mayon-clash/config.yaml) = 600")
machine.succeed("test $(stat -c %U /run/mayon-clash/mihomo.sock) = trial")
# Mihomo deliberately chmods its socket 0666; the owner-only runtime directory is the boundary.
machine.fail("runuser -u nobody -- curl --max-time 2 --unix-socket /run/mayon-clash/mihomo.sock http://localhost/version")
status, output = machine.execute("curl --fail --max-time 10 http://198.19.0.2:18081/ | grep 'synthetic TUN proxy response'")
if status:
    machine.log(machine.succeed("journalctl -u mayon-clash -u synthetic-subscription --no-pager -o cat"))
assert status == 0, output
machine.succeed("curl --max-time 25 http://198.19.0.2:18081/hold > /tmp/hold.out 2>/tmp/hold.err &")
machine.wait_until_succeeds("curl -s --unix-socket /run/mayon-clash/mihomo.sock http://localhost/connections | grep '198.19.0.2'")
machine.succeed("dig +time=2 +tries=1 +short @198.18.0.1 synthetic.invalid A | grep '^198\\.18\\.'")
machine.succeed(user("clashtui-mayon settings tun false"))
machine.wait_until_fails("ip link show mayon-clash")
machine.succeed(user("clashtui-mayon settings tun true"))
machine.wait_until_succeeds("ip link show mayon-clash")
machine.succeed(user("clashtui-mayon settings mode direct"))
machine.succeed(user("clashtui-mayon settings mode rule"))
machine.succeed(user("clashtui-mayon profile update all"))
# Deliberately stop as soon as the interface exists, before full initialization.
# Repeating exposes upstream 1.19.24's pre-signal-handler rule-leak race.
for cycle in range(3):
    machine.succeed(user("systemctl --no-ask-password restart mayon-clash.service"))
    if cycle:
        machine.wait_until_succeeds("ip link show mayon-clash")
    machine.succeed(user("systemctl --no-ask-password stop mayon-clash.service"))
    machine.wait_until_fails("ip link show mayon-clash")
machine.wait_until_fails("ip link show mayon-clash")
machine.succeed("test ! -e /run/mayon-clash/mihomo.sock")
machine.succeed("ip -j route show table all > /tmp/routes-after.json")
machine.succeed("ip -j rule show > /tmp/rules-after.json")
# DHCP/IPv6 lifetimes vary with time; compare routes after removing only expiry clocks.
machine.succeed("python3 -c 'import json; a=lambda p: sorted([{k:v for k,v in r.items() if k not in (\"expires\",\"cache\")} for r in json.load(open(p))],key=str); b=a(\"/tmp/routes-before.json\"); c=a(\"/tmp/routes-after.json\"); print(b,c) if b!=c else None; assert b==c; d=a(\"/tmp/rules-before.json\"); e=a(\"/tmp/rules-after.json\"); print(d,e) if d!=e else None; assert d==e'")
machine.fail("curl --max-time 2 http://198.19.0.2:18081/")
