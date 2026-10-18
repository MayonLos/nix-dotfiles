{
  pkgs,
  home,
  quotedHome,
}:
pkgs.runCommand "default-tools-runtime" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  mkdir -p spy "$out"
  cat > spy/program <<'SH'
  #!${pkgs.runtimeShell}
  printf '%s\0' "$@" > "$CAPTURE"
  SH
  chmod +x spy/program
  for program in kitty nvim firefox thunar; do ln -s program "spy/$program"; done
  export PATH="$PWD/spy:$PATH"
  export CAPTURE="$out/terminal.argv"
  ${quotedHome.home.sessionVariables.TERMINAL} 'file with spaces' '$(touch injected)' '"quoted"' ""
  test ! -e injected
  export CAPTURE="$out/editor.argv"
  ${home.home.sessionVariables.EDITOR} 'notes with spaces.md'
  export CAPTURE="$out/browser.argv"
  ${home.home.sessionVariables.BROWSER} 'https://example.invalid/?q=a b&x=$HOME'
  export CAPTURE="$out/files.argv"
  ${home.home.path}/bin/workspace-files '/tmp/a directory'
  python3 - "$out" <<'PY'
  from pathlib import Path
  import sys
  root = Path(sys.argv[1])
  def args(name):
      return (root / name).read_bytes().split(b'\0')[:-1]
  assert args('terminal.argv') == [b'--class', b'work space', b'--title', b'literal $HOME; $(touch injected)', b'file with spaces', b'$(touch injected)', b'"quoted"', b""]
  assert args('editor.argv') == [b'notes with spaces.md']
  assert args('browser.argv') == [b'https://example.invalid/?q=a b&x=$HOME']
  assert args('files.argv') == [b'/tmp/a directory']
  PY
  grep -Fq 'text/plain=code.desktop' ${home.xdg.configFile."mimeapps.list".source}
  test -f ${home.home.path}/share/applications/code.desktop
  test -f ${home.home.path}/share/applications/firefox.desktop
  test -f ${home.home.path}/share/applications/thunar.desktop
''
