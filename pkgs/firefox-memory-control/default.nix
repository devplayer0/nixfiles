{
  lib,
  firefox-unwrapped,
  wrapFirefox,
  writeText,
  writeScriptBin,
  symlinkJoin,
  python3,
  lowAvailableMiB ? 2048,
  highAvailableMiB ? 3072,
  pollIntervalMs ? 1000,
  minInactiveMs ? 300000,
}:
let
  autoConfig = writeText "firefox-memory-control.js" ''
    defaultPref("firefox.memoryControl.enabled", true);
    defaultPref("firefox.memoryControl.lowAvailableMiB", ${toString lowAvailableMiB});
    defaultPref("firefox.memoryControl.highAvailableMiB", ${toString highAvailableMiB});
    defaultPref("firefox.memoryControl.pollIntervalMs", ${toString pollIntervalMs});
    defaultPref("firefox.memoryControl.minInactiveMs", ${toString minInactiveMs});

    ${builtins.readFile ./autoconfig.js}
  '';

  firefox = wrapFirefox firefox-unwrapped {
    extraAutoConfig = ''
      pref("general.config.sandbox_enabled", false);
    '';
    extraPrefsFiles = [ autoConfig ];
  };

  freeMemory = writeScriptBin "firefox-free-memory" ''
    #!${python3}/bin/python3
    ${builtins.readFile ./firefox-free-memory.py}
  '';
in
symlinkJoin {
  name = "firefox-memory-control-${firefox.version}";
  paths = [ firefox freeMemory ];

  meta = firefox.meta // {
    description = "Firefox with memory-pressure tab unloading and an on-demand reclaim utility";
    mainProgram = "firefox";
    platforms = lib.platforms.linux;
  };
}
