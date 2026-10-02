{ lib, pkgs, source }:

let
  version = (builtins.fromTOML (builtins.readFile ../native/Cargo.toml)).package.version;
  libraryFile = if pkgs.stdenv.hostPlatform.isDarwin then "libkeyboard_sound.dylib" else "libkeyboard_sound.so";
  native = pkgs.rustPlatform.buildRustPackage {
    pname = "keyboard-sound-native";
    inherit version;
    src = source;
    cargoRoot = "native";
    buildAndTestSubdir = "native";
    cargoLock.lockFile = ../native/Cargo.lock;
    nativeBuildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.pkg-config ];
    buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.alsa-lib ];
    doInstallCheck = pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform;
    nativeInstallCheckInputs = [ pkgs.neovim-unwrapped ];
    installCheckPhase = ''
      runHook preInstallCheck
      export HOME="$(mktemp -d)"
      KEYBOARD_SOUND_LIBRARY="$out/lib/${libraryFile}" nvim --headless -u NONE -l tests/native.lua
      runHook postInstallCheck
    '';
    meta = {
      description = "rodio shared library for Neovim keyboard audio";
      homepage = "https://github.com/vimhead/keyboard-sound.nvim";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux ++ lib.platforms.darwin;
    };
  };
  plugin = pkgs.vimUtils.buildVimPlugin {
    pname = "keyboard-sound.nvim";
    inherit version;
    src = source;
    postInstall = ''
      rm "$out/build.lua"
      mkdir -p "$out/native/target/release"
      ln -s ${native}/lib/${libraryFile} "$out/native/target/release/${libraryFile}"
    '';
    passthru = {
      inherit native;
      nativeLibrary = "${native}/lib/${libraryFile}";
    };
    meta = {
      description = "Insert-mode keyboard clicks with a preloaded native audio mixer";
      homepage = "https://github.com/vimhead/keyboard-sound.nvim";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux ++ lib.platforms.darwin;
    };
  };
in
{
  inherit native plugin;
}
