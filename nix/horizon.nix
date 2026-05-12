{
  buildDartApplication,
  lib,
  runCommand,
  yj,
  makeWrapper,
  curl,
  jq,
  whisper-cpp,
  ffmpeg,
  poppler-utils,
}:
let
  # buildDartApplication needs pubspec.lock as parsed Nix data.
  # The file on disk is YAML; convert to JSON via yj at eval time.
  pubspecLockJson = runCommand "pubspec.lock.json" { } ''
    ${yj}/bin/yj -yj < ${../pubspec.lock} > $out
  '';
in
buildDartApplication {
  pname = "horizon";
  version = "0.1.0";

  src = lib.cleanSource ../.;

  pubspecLock = lib.importJSON pubspecLockJson;

  # @freezed-generated files (*.freezed.dart) are committed to
  # source so this build doesn't need to run build_runner inside
  # the Nix sandbox (which would fight dartConfigHook's read-only
  # source tree). After editing any @freezed type, run
  # `dart run build_runner build` locally and commit the diff.

  # Compile bin/horizon.dart → $out/bin/horizon
  dartEntryPoints = {
    "horizon" = "bin/horizon.dart";
  };

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    # dartInstallHook puts the compiled binary at $out/horizon (not
    # $out/bin/horizon). Move it where nix run / meta.mainProgram
    # expects it, and stage the templates bundle into
    # $out/share/horizon. The allowlist now lives under
    # templates/_horizon/system/allowlist.yaml — bootstrapped into
    # the vault on first run, then hot-reloaded from there.
    mkdir -p $out/bin $out/share/horizon
    mv $out/horizon $out/bin/horizon
    cp -r templates $out/share/horizon/templates
  '';

  # Wrap during fixupPhase, after install/chmod is settled. Sets
  # HORIZON_TEMPLATES so the binary finds the bundled bootstrap
  # source regardless of cwd, and puts curl/jq/whisper-cpp/ffmpeg/
  # pdftotext on PATH for the bash tool templates that need them.
  postFixup = ''
    wrapProgram $out/bin/horizon \
      --set-default HORIZON_TEMPLATES $out/share/horizon/templates \
      --prefix PATH : ${
        lib.makeBinPath [
          curl
          jq
          whisper-cpp
          ffmpeg
          poppler-utils
        ]
      }
  '';

  meta = with lib; {
    description = "Personal multi-agent assistant with vault-resident capabilities";
    homepage = "https://github.com/purplenoodlesoop/horizon";
    license = licenses.mit;
    mainProgram = "horizon";
    platforms = platforms.unix;
  };
}
