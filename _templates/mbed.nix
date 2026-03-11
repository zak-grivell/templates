{ pkgs, ... }: let
  tool_chain = "gcc_arm";
  mbed_target = "LPC1768";
  system = pkgs.stdenv.hostPlatform.system;
in {

  overlays = [
    (final: prev: {
      mbed-tools = pkgs.python311Packages.buildPythonPackage rec {
        pname = "mbed-tools";
        version = "7.58.0";

        src = pkgs.fetchPypi {
          inherit pname version;
          sha256 = "sha256-tFMpKkb1z86eYboQxPGbhVLBrUzx5xOVwXCieeXYHB0==";
        };

        pyproject = true;

        build-system = with pkgs.python311Packages; [
          setuptools
          setuptools-scm
        ];

        propagatedBuildInputs = with pkgs.python311Packages; [
          click
          pyserial
          intelhex
          prettytable
          packaging
          cmsis-pack-manager
          python-dotenv
          gitpython
          tqdm
          tabulate
          requests
          jinja2
          setuptools
          future
        ];

        doCheck = false;

        meta = with pkgs.lib; {
          description = "Arm Mbed command line tools";
          homepage = "https://github.com/ARMmbed/mbed-tools";
          license = licenses.asl20;
        };
      };

      gcc-arm-embedded = pkgs.stdenv.mkDerivation {
        pname = "gcc-arm-embedded";
        version = "10.3-2021.10";

        platform =
          {
            aarch64-darwin = "mac";
            aarch64-linux = "aarch64";
            x86_64-linux = "x86_64";
          }
          .${system}
            or (throw "Unsupported system: ${pkgs.stdenv.hostPlatform.system}");

        src = pkgs.fetchurl {
          url = "https://developer.arm.com/-/media/files/downloads/gnu-rm/10.3-2021.10/gcc-arm-none-eabi-10.3-2021.10-mac.tar.bz2";
          sha256 =
            {
              aarch64-darwin = "+2E9rLJRSfFA9z/p/2w4C7QzKOa/gTRzmG6RJ+K8KDs=";
              aarch64-linux = "2d465847eb1d05f876270494f51034de9ace9abe87a4222d079f3360240184d3";
              x86_64-linux = "8f6903f8ceb084d9227b9ef991490413014d991874a1e34074443c2a72b14dbd";
            }
            .${pkgs.stdenv.hostPlatform.system}
              or (throw "Unsupported system: ${pkgs.stdenv.hostPlatform.system}");
        };

        dontConfigure = true;
        dontBuild = true;
        dontPatchELF = true;
        dontStrip = true;

        installPhase = ''
          mkdir -p $out
          cp -r * $out
          rm $out/bin/{arm-none-eabi-gdb-py,arm-none-eabi-gdb-add-index-py} || :
        '';

        preFixup = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
          find $out -type f | while read f; do
            patchelf "$f" > /dev/null 2>&1 || continue
            patchelf --set-interpreter $(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker) "$f" || true
            patchelf --set-rpath ${
              pkgs.lib.makeLibraryPath [
                "$out"
                pkgs.stdenv.cc.cc
                pkgs.ncurses6
                pkgs.libxcrypt-legacy
                pkgs.xz
                pkgs.zstd
              ]
            } "$f" || true
          done
        '';
      };
    })
  ];


  packages = with pkgs; [
    clang-tools

    (pkgs.python311.withPackages (
      ps: with ps; [
        future
        ninja
        prettytable
        intelhex
        pip
      ]
    ))

    mbed-tools
    gcc-arm-embedded
    cmake
  ];

  files.".clangd".yaml = {
    CompileFlags = {
      Add = [
        "--target=arm-none-eabi"
      ];
      CompilationDatabase = ".";
    };

    Index = {
      StandardLibrary = true;
    };
  };

  files.".mbedignore".text = ''
      .devenv
      .direnv
      .nix
      result
      .git
    '';

  env.CLANGD_FLAGS = "--query-driver=${pkgs.gcc-arm-embedded}/bin/arm-none-eabi-*";

  scripts.build.exec = ''
    mbed-tools compile -t ${tool_chain} -m ${mbed_target}
  '';

  scripts.flash.exec = ''
    mbed-tools compile -t ${tool_chain} -m ${mbed_target} -f
  '';

  scripts.compile-db.exec = ''
    set -e

    # 1. Normal mbed-tools build (creates the CMake tree)
    mbed-tools compile -t ${tool_chain} -m ${mbed_target}

    BUILD_DIR="cmake_build/${mbed_target}/develop/GCC_ARM/"

    # 2. Ask CMake to export compile_commands.json
    cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON "$BUILD_DIR"

    # 3. Symlink into project root for clangd
    ln -sf "$BUILD_DIR/compile_commands.json" compile_commands.json

    echo "✔ compile_commands.json ready"
  '';
}
