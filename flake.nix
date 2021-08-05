# Build the container image using:
#   nix build -L .#containerImage
#   TMPDIR=/tmp/podman podman load < result
{
  description = "The matrix-bot application";

  nixConfig.bash-prompt = "[nix]λ ";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    matrix-client.url = "github:softwarefactory-project/matrix-client-haskell";
    matrix-client.flake = false;
  };

  outputs = { self, nixpkgs, flake-utils, matrix-client }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        config = { };

        compilerVersion = "8104";
        compiler = "ghc" + compilerVersion;
        overlays = [
          (final: prev: {
            haskell-language-server = prev.haskell-language-server.override {
              supportedGhcVersions = [ compilerVersion ];
            };

            myHaskellPackages = prev.haskell.packages.${compiler}.override {
              overrides = hpFinal: hpPrev: {
                matrix-client =
                  hpPrev.callCabal2nix "matrix-client" matrix-client { };
                matrix-bot =
                  hpPrev.callCabal2nix "matrix-bot" ./. { };
              };
            };
          })
        ];

        pkgs = import nixpkgs { inherit config overlays system; };

      in rec {
        defaultPackage = packages.matrix-bot;
        defaultApp = apps.matrix-bot;
        defaultExe = pkgs.haskell.lib.justStaticExecutables defaultPackage;
        defaultContainerImage = pkgs.dockerTools.buildLayeredImage {
          name = "matrix-bot";
          contents = [ defaultExe ];
          config = {
            Entrypoint = [ "matrix-bot" ];
          };
        };

        packages = with pkgs.myHaskellPackages; {
          inherit matrix-bot;
          containerImage = defaultContainerImage;
        };

        apps.matrix-bot =
          flake-utils.lib.mkApp { drv = packages.matrix-bot; };

        devShell = pkgs.myHaskellPackages.shellFor {
          packages = p: [ p.matrix-bot ];

          buildInputs = with pkgs.myHaskellPackages; [
            cabal-install
            hlint
            pkgs.haskell-language-server
          ];

          withHoogle = true;
        };
      });
}
