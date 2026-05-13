{ config, lib, pkgs, ... }:

let
  cfg = config.services.horizon;
in
{
  options.services.horizon = {
    enable = lib.mkEnableOption "Horizon personal assistant";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.horizon or null;
      defaultText = lib.literalExpression "pkgs.horizon";
      description = ''
        The `horizon` package to run. `pkgs.horizon` is only present if
        the flake's overlay is applied; otherwise set this explicitly,
        e.g. `inputs.horizon.packages.''${pkgs.system}.default`.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "horizon";
      description = ''
        User to run the service as. The default `horizon` user is
        created by this module; a non-default value must be defined
        elsewhere.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "horizon";
      description = ''
        Group to run the service as. The default `horizon` group is
        created by this module; other vault writers (Syncthing,
        external integrations) should join it for shared vault access.
      '';
    };

    vault = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/horizon/vault";
      description = ''
        Absolute path to the Obsidian vault. Must be writable by the
        service user. Do NOT use a Nix path literal — that would copy
        the vault into the store.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/etc/horizon/horizon.env";
      description = ''
        Systemd `EnvironmentFile=` containing tokens
        (`TELEGRAM_TOKEN`, `LLM_TOKEN`, optional `TAVILY_TOKEN`,
        `TELEGRAM_USERNAME`). File must be readable by the service
        user (e.g. mode 0640 root:horizon).
      '';
    };

    extraAllowlists = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str lib.types.path);
      default = [ ];
      example = lib.literalExpression ''
        [ inputs.potentiality.nixosModules.horizonIntegration ]
      '';
      description = ''
        Additional allowlist YAML fragments passed via
        `--extra-allowlist`. Typically Nix store paths from
        integration modules that need to add tools without touching
        the user-editable vault allowlist. Tool name conflicts
        across sources are fatal at startup.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--heartbeat" "60" ];
      description = "Extra CLI arguments passed to the horizon binary.";
    };

    umask = lib.mkOption {
      type = lib.types.str;
      default = "0002";
      description = ''
        Service `UMask=`. Defaults to `0002` so files written by
        Horizon into the vault are group-writable — required when
        external integrations (e.g. Potentiality running as a
        different user in the same group) need to write back into
        the same task directories.
      '';
    };

    path = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [ bash curl jq ];
      defaultText = lib.literalExpression "with pkgs; [ bash curl jq ]";
      description = ''
        Packages on the service's PATH. Bash command templates in
        the allowlist rely on these — `bash` for templating itself,
        and the others for the default tool surface (`fetch_url`,
        `web_search`, etc.). Replace if you want to override entirely;
        most consumers should use `extraPath` to add packages on top.
      '';
    };

    extraPath = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.potentiality ]";
      description = ''
        Additional packages appended to the service's PATH after
        `path`. Use this to add binaries that integration modules
        need (e.g. `pot` for the Potentiality integration) without
        having to restate the default list.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = ''
          services.horizon.package is not set and `pkgs.horizon` is
          not in scope. Set it explicitly, e.g.
            services.horizon.package = inputs.horizon.packages.''${pkgs.system}.default;
        '';
      }
      {
        assertion = lib.hasPrefix "/" cfg.vault;
        message = "services.horizon.vault must be an absolute path.";
      }
    ];

    users = {
      users = lib.mkIf (cfg.user == "horizon") {
        horizon = {
          isSystemUser = true;
          group = cfg.group;
          home = "/var/lib/horizon";
        };
      };
      groups = lib.mkIf (cfg.group == "horizon") {
        horizon = { };
      };
    };

    systemd.services.horizon = {
      description = "Horizon personal assistant";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      path = cfg.path ++ cfg.extraPath;

      serviceConfig = {
        ExecStart = lib.concatStringsSep " " (
          [
            (lib.getExe cfg.package)
            "--vault" (lib.escapeShellArg cfg.vault)
          ]
          ++ lib.concatMap
            (p: [ "--extra-allowlist" (lib.escapeShellArg (toString p)) ])
            cfg.extraAllowlists
          ++ map lib.escapeShellArg cfg.extraArgs
        );

        User = cfg.user;
        Group = cfg.group;
        StateDirectory = "horizon";
        StateDirectoryMode = "0770";
        WorkingDirectory = "/var/lib/horizon";
        Restart = "always";
        RestartSec = 10;

        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        UMask = cfg.umask;
      } // lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
    };
  };
}
