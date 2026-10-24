{
  base,
  tint,
  percent,
}:
let
  digits = [
    "0"
    "1"
    "2"
    "3"
    "4"
    "5"
    "6"
    "7"
    "8"
    "9"
    "a"
    "b"
    "c"
    "d"
    "e"
    "f"
  ];
  toHex =
    value:
    let
      hi = builtins.div value 16;
      lo = value - (16 * hi);
    in
    "${builtins.elemAt digits hi}${builtins.elemAt digits lo}";
  channel = color: offset: (builtins.fromTOML "value = 0x${builtins.substring offset 2 color}").value;
  component =
    offset:
    let
      from = channel base offset;
      to = channel tint offset;
      value = builtins.div (from * (100 - percent) + to * percent + 50) 100;
    in
    toHex value;
in
"#${component 1}${component 3}${component 5}"
