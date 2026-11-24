{ lib, pkgs, inputs, config, options, ... }:
let
  inherit (lib) mkIf optional optionalAttrs mapAttrs attrValues types;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.agents;
  agentPkgs = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  slopGuide = "${pkgs.slop-broker}/share/slop-broker/slop-tools.md";

  # Claude takes a rule file each; Codex takes one `AGENTS.md`
  rules = optionalAttrs cfg.slop.enable { slop = slopGuide; }
    // mapAttrs (name: text: pkgs.writeText "${name}.md" text) cfg.rules;
  codexContext = pkgs.concatText "AGENTS.md" (attrValues rules);
in
{
  options.my.agents = {
    enable = mkBoolOpt' false "Whether to install and configure coding agents (Claude Code, Codex).";
    slop.enable = mkBoolOpt' false "Whether agents use the `slop` client for privileged operations.";
    rules = mkOpt' (types.attrsOf types.lines) { }
      "Instructions for every agent, by name: a Claude rule each, and appended to Codex's `AGENTS.md`.";
  };

  config = mkIf cfg.enable {
    home.packages = optional cfg.slop.enable pkgs.slop-broker;

    programs = {
      # TODO: Remove mutableSettings guard when Home Manager 26.11 releases; 26.05 lacks it.
      codex = {
        enable = true;
        package = agentPkgs.codex;
        settings.sandbox_workspace_write.network_access = true;
        settings.tui = {
          status_line = [
            "model-with-reasoning"
            "current-dir"
            "five-hour-limit"
            "weekly-limit"
            "context-used"
            "context-window-size"
            "total-input-tokens"
            "total-output-tokens"
            "used-tokens"
          ];
          status_line_use_colors = true;
        };
      } // optionalAttrs (options.programs.codex ? mutableSettings) {
        mutableSettings = true;
      } // optionalAttrs (rules != { }) {
        context = "${codexContext}";
      };

      claude-code = {
        enable = true;
        package = agentPkgs.claude-code;
        inherit rules;
        settings = {
          model = "opus";
          theme = "auto";
          statusLine = {
            type = "command";
            command = ./claude-statusline.sh;
            padding = 0;
          };
        };
      };
    };
  };
}
