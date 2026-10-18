{
  pkgs,
  profile,
  rules,
}:
{
  udev = pkgs.runCommand "den-embedded-udev" { } ''
    test -s ${rules}/60-openocd.rules
    test -s ${rules}/49-stlinkv2.rules
    test -s ${rules}/49-stlinkv3.rules
    grep -Eq '0483.*3748.*TAG\+="uaccess"' ${rules}/60-openocd.rules
    sed -z 's/\\\n[[:space:]]*/ /g' ${rules}/49-stlinkv2.rules > stlink.rules
    grep -Eq '0483.*3748.*TAG\+="uaccess"' stlink.rules
    for source in ${pkgs.stlink}/lib/udev/rules.d/*.rules; do
      rule=${rules}/$(basename "$source")
      test -s "$rule"
      if grep -q 'MODE:="0666"' "$rule"; then
        echo "World-writable ST-Link rule remains: $rule" >&2
        exit 1
      fi
      expected=$(grep -c '^[[:space:]]*MODE:="0666"' "$source")
      actual=$(grep -c '^[[:space:]]*MODE:="0660", TAG+="uaccess"' "$rule")
      test "$actual" -eq "$expected"
      grep -q 'SYMLINK+=' "$rule"
      diff <(grep 'SYMLINK+=' "$source") <(grep 'SYMLINK+=' "$rule")
    done
    test "$(grep -c '0483.*df11.*uaccess' ${rules}/70-stm32-dfu.rules)" = 1
    mkdir -p "$out"
    ln -s ${rules} "$out/rules"
  '';
  tools = pkgs.runCommand "den-embedded-tools" { } ''
    mkdir -p "$out"
    printf 'int main(void) { return 0; }\n' > smoke.c
    ${profile}/bin/arm-none-eabi-gcc -mcpu=cortex-m4 -mthumb -g -ffreestanding -c smoke.c -o "$out/smoke.o"
    ${profile}/bin/arm-none-eabi-readelf -h "$out/smoke.o" > "$out/elf.txt"
    grep -Eq 'Machine:.*ARM' "$out/elf.txt"
    ${profile}/bin/arm-none-eabi-gdb -nx -batch -ex "file $out/smoke.o" -ex 'info address main' > "$out/cross-gdb.txt"
    grep -q 'Symbol "main"' "$out/cross-gdb.txt"
    ${profile}/bin/gdb -nx -batch -ex 'show data-directory' > "$out/host-gdb.txt"
    ${profile}/bin/openocd --version > "$out/openocd.txt" 2>&1
    ${profile}/bin/probe-rs --version > "$out/probe-rs.txt"
    ${profile}/bin/tio --version > "$out/tio.txt"
  '';
}
