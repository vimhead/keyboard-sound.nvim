{
  description = "Neovim keyboard sounds with a rodio shared library";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forSystems = nixpkgs.lib.genAttrs systems;
      packagesFor = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./nix/package.nix { inherit pkgs; lib = pkgs.lib; source = self; };
    in
    {
      packages = forSystems (system:
        let packages = packagesFor system;
        in { default = packages.plugin; inherit (packages) native; }
      );
      checks = forSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          plugin = self.packages.${system}.default;
          lua = pkgs.runCommand "keyboard-sound-lua-tests" {
            nativeBuildInputs = [ pkgs.neovim-unwrapped ];
          } ''
            export HOME="$(mktemp -d)"
            cd ${self}
            for test in run backend installer; do
              nvim --headless -u NONE -l "tests/$test.lua"
            done
            touch "$out"
          '';
        }
      );
    };
}
