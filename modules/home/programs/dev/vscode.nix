{ pkgs, ... }:
{
  # FHS 变体，而不是给普通 vscode 手工补 LD_LIBRARY_PATH。
  #
  # 扩展自带的预编译二进制需要一堆系统库，缺一个就静默不工作：cpptools 的
  # OpenDebugAD7 要 libstdc++，而当初装 STM32Cube 时它的 node-usb 绑定还要
  # libudev.so.1 —— 手工 wrapper 只塞了 stdenv.cc.cc.lib + libusb1，
  # libudev 没覆盖到，打地鼠打不完。
  # vscode-fhs 的 targetPkgs 里已经有 udev/libudev0-shim/glibc/icu/nss 等，
  # 一次性解决这一类问题。要再加库用 pkgs.vscode.fhsWithPackages (ps: [ ... ])。
  programs.vscode = {
    enable = true;
    package = pkgs.vscode-fhs;
  };
}
