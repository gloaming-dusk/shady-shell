# NixOS module: `programs.shady-shell.enable = true;` installs the shell and
# the PAM services its lock screen checks passwords with. Shady starts it
# from PATH; Gloam turns this on with the rest of the desktop.
self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.shady-shell;
in
{
  options.programs.shady-shell = {
    enable = lib.mkEnableOption "shady-shell, the desktop shell for the Shady compositor";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "shady-shell.packages.\${system}.default";
      description = "The shady-shell package to use.";
    };

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Packages with shell plugins in `lib/shady/shell-plugins`, added to
        `SHADY_SHELL_PLUGIN_PATH`. A plugin runs inside the shell, which sees
        the lock screen's password.
      '';
    };

    lock.fingerprint = lib.mkOption {
      type = lib.types.bool;
      default = config.services.fprintd.enable;
      defaultText = lib.literalExpression "config.services.fprintd.enable";
      description = ''
        Let the lock screen (Tide's) unlock with a fingerprint, while the
        password field stays usable: the reader is checked through its own
        PAM service, `shady-lock-fingerprint`, next to `shady-lock`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    environment.sessionVariables.SHADY_SHELL_PLUGIN_PATH =
      lib.mkIf (cfg.plugins != [ ]) (lib.makeSearchPath "lib/shady/shell-plugins" cfg.plugins);

    # The lock screen checks passwords through shady-auth with these. The
    # password service never waits on a fingerprint reader.
    security.pam.services.shady-lock = {
      fprintAuth = false;
    };
    security.pam.services.shady-lock-fingerprint = lib.mkIf cfg.lock.fingerprint {
      text = ''
        auth required ${config.services.fprintd.package}/lib/security/pam_fprintd.so
        account required ${pkgs.linux-pam}/lib/security/pam_unix.so
      '';
    };

    # The shell lays out text with Pango and draws nothing without fontconfig.
    fonts.fontconfig.enable = true;
  };
}
