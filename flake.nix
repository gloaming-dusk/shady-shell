{
  description = "shady-shell, the Lua-scripted desktop shell for the Shady compositor";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  # Only for the headless tests and trying the shell: the build itself needs
  # no compositor.
  inputs.shady.url = "github:gloaming-dusk/shady";
  inputs.shady.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, shady, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      shellFor = pkgs: pkgs.callPackage ./nix/package.nix { };
    in {
      packages = forAllSystems (pkgs: rec {
        shady-shell = shellFor pkgs;
        default = shady-shell;
      });

      overlays.default = final: prev: {
        shady-shell = shellFor final;
      };

      # `nix run github:gloaming-dusk/shady-shell`: Shady in a window of the
      # current session, with this shell and its default.lua.
      apps = forAllSystems (pkgs: let
        shell = shellFor pkgs;
        compositor = shady.packages.${pkgs.stdenv.hostPlatform.system}.default;
        try = pkgs.writeShellScript "shady-shell-try" ''
          export SHADY_RICE=none
          export SHADY_SHELL_BIN=${shell}/bin/shady-shell
          exec ${compositor}/bin/shady -s "${shell}/bin/shady-shell & exec ${pkgs.foot}/bin/foot"
        '';
      in {
        default = { type = "app"; program = "${try}"; };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          strictDeps = true;
          inputsFrom = [ (shellFor pkgs) ];
          # The compositor the headless tests (tests/run.sh) run the shell in.
          packages = [ shady.packages.${pkgs.stdenv.hostPlatform.system}.default ]
            ++ (with pkgs; [ gdb grim wl-clipboard wtype foot ]);
        };
      });
    };
}
