{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    bun2nix = {
      url = "github:nix-community/bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      ...
    }@inputs:
    with builtins;
    with nixpkgs.lib;

    let
      doubles = import inputs.systems;
      forAllSystems = genAttrs doubles;

      pkgs_gen =
        { ... }@args:
        import nixpkgs (
          {
            overlays = [ 
              inputs.bun2nix.overlays.default 
              
              (final: prev: {
                bun = prev.bun.overrideAttrs (oldAttrs: rec {
                  version = "1.3.13";
                  src = prev.fetchurl {
                    url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-x64-baseline.zip";
                    hash = "sha256-nYokKSpwaAkCBdqsCloiP19pc29Sh+N7+I07QDHtx1A=";
                  };
                });
              })
            ];
          }
          // args
        );

      importBunLock =
        { pkgs, src }:
        pkgs.stdenv.mkDerivation {
          inherit src;

          name = "bun.nix";

          nativeBuildInputs = with pkgs; [
            bun2nix
          ];

          buildPhase = ''
            bun2nix -o bun.nix
          '';

          installPhase = ''
            cp bun.nix $out
          '';
        };

      iloader_gen =
        {
          pkgs,
          tools ? [ ],
          specialArgs ? { },
        }:
        pkgs.rustPlatform.buildRustPackage (
          let
            src = cleanSource ./.;
            json = fromJSON (readFile (src + "/package.json"));
          in
          final:
          {
            pname = json.name;
            inherit (json) version;

            inherit src;
            bunDeps = pkgs.bun2nix.fetchBunDeps {
              bunNix = importBunLock { inherit pkgs src; };
            };
            cargoRoot = "src-tauri";
            cargoLock.lockFile = src + "/${final.cargoRoot}/Cargo.lock";
            buildAndTestSubdir = final.cargoRoot;

            dontUseBunBuild = true;
            dontUseBunCheck = true;

            nativeBuildInputs =
              with pkgs;
              [
                cargo-tauri.hook
                bun2nix.hook
                pkg-config
                jq
                moreutils
              ]
              ++ optionals pkgs.stdenv.hostPlatform.isLinux [ wrapGAppsHook4 ]
              ++ tools;

            buildInputs = optionals pkgs.stdenv.hostPlatform.isLinux (
              with pkgs;
              [
                glib-networking
                openssl
                webkitgtk_4_1
              ]
            );

            postPatch = ''
              jq \
                '.plugins.updater.endpoints = [ ]
                | .bundle.createUpdaterArtifacts = false' \
                ${final.cargoRoot}/tauri.conf.json \
                | sponge ${final.cargoRoot}/tauri.conf.json
            '';
          }
          // specialArgs
        );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgs_gen { inherit system; };
          iloader = iloader_gen { inherit pkgs; };
        in
        {
          inherit iloader;
          default = iloader;
        }
      );
      formatter = forAllSystems (
        system:
        let
          pkgs = pkgs_gen { inherit system; };
        in
        inputs.treefmt-nix.lib.mkWrapper pkgs {
          programs.nixfmt.enable = true;
        }
      );
    };
}
