// This file runs as privileged Firefox AutoConfig code. Keep it in the Nix store.
(() => {
  "use strict";

  const { classes: Cc, interfaces: Ci, utils: Cu } = Components;
  Cu.importGlobalProperties(["IOUtils"]);
  const Services = {
    appinfo: Cc["@mozilla.org/xre/app-info;1"].getService(Ci.nsIXULRuntime),
    console: Cc["@mozilla.org/consoleservice;1"].getService(Ci.nsIConsoleService),
    env: Cc["@mozilla.org/process/environment;1"].getService(Ci.nsIEnvironment),
    prefs: Cc["@mozilla.org/preferences-service;1"].getService(Ci.nsIPrefBranch),
  };
  const { TabUnloader } = ChromeUtils.importESModule(
    "moz-src:///browser/components/tabbrowser/TabUnloader.sys.mjs"
  );

  const PREFIX = "firefox.memoryControl.";
  const MiB = 1024 * 1024;
  const log = message => {
    const line = `[firefox-memory-control] ${message}`;
    Services.console.logStringMessage(line);
    if (typeof dump === "function") {
      dump(`${line}\n`);
    }
  };

  const sleep = milliseconds =>
    new Promise(resolve => {
      const timer = Cc["@mozilla.org/timer;1"].createInstance(Ci.nsITimer);
      timer.initWithCallback(resolve, milliseconds, Ci.nsITimer.TYPE_ONE_SHOT);
    });

  const prefInt = name => Services.prefs.getIntPref(PREFIX + name);
  const prefBool = name => Services.prefs.getBoolPref(PREFIX + name);

  // procfs files report a size of zero, so IOUtils reads /proc/meminfo as empty.
  // nsIScriptableInputStream also rejects reads larger than that reported size;
  // nsIConverterInputStream reads until EOF without relying on it.
  function availableMemory() {
    const file = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
    file.initWithPath("/proc/meminfo");
    const fileStream = Cc["@mozilla.org/network/file-input-stream;1"].createInstance(
      Ci.nsIFileInputStream
    );
    fileStream.init(file, 0x01, 0, 0);
    const input = Cc["@mozilla.org/intl/converter-input-stream;1"].createInstance(
      Ci.nsIConverterInputStream
    );
    input.init(fileStream, "UTF-8", 0, 0);
    const chunk = {};
    let meminfo = "";
    while (input.readString(4096, chunk)) {
      meminfo += chunk.value;
    }
    input.close();

    const match = /^MemAvailable:\s+(\d+)\s+kB$/m.exec(meminfo);
    if (!match) {
      throw new Error("MemAvailable is absent from /proc/meminfo");
    }
    return Number(match[1]) * 1024;
  }

  async function unloadOne(minInactiveMs) {
    const sorted = await TabUnloader.getSortedTabs(minInactiveMs);
    const candidate = sorted.find(tab => TabUnloader.isDiscardable(tab));
    if (!candidate) {
      return null;
    }

    const estimatedBytes = candidate.memory || 0;
    const unloaded = await TabUnloader.unloadLeastRecentlyUsedTab(minInactiveMs);
    return unloaded ? { estimatedBytes } : null;
  }

  function runtimePaths() {
    const runtimeDir = Services.env.get("XDG_RUNTIME_DIR");
    if (!runtimeDir || !runtimeDir.startsWith("/")) {
      throw new Error("XDG_RUNTIME_DIR is not an absolute path");
    }

    const root = `${runtimeDir}/firefox-memory-control`;
    return {
      root,
      requests: `${root}/requests`,
      processing: `${root}/processing`,
      responses: `${root}/responses`,
    };
  }

  async function ensureRuntimeDirectories(paths) {
    for (const path of Object.values(paths)) {
      await IOUtils.makeDirectory(path, { ignoreExisting: true, permissions: 0o700 });
    }
  }

  async function claimRequest(paths) {
    const children = await IOUtils.getChildren(paths.requests);
    for (const requestPath of children.sort()) {
      if (!requestPath.endsWith(".json")) {
        continue;
      }

      const leaf = requestPath.slice(requestPath.lastIndexOf("/") + 1);
      const claimed = `${paths.processing}/${leaf}.${Services.appinfo.processID}`;
      try {
        await IOUtils.move(requestPath, claimed, { noOverwrite: true });
        return claimed;
      } catch (error) {
        // Another Firefox instance can win the atomic move.
      }
    }
    return null;
  }

  async function writeResponse(paths, id, response) {
    const finalPath = `${paths.responses}/${id}.json`;
    const temporaryPath = `${finalPath}.${Services.appinfo.processID}.tmp`;
    await IOUtils.writeUTF8(temporaryPath, JSON.stringify(response));
    await IOUtils.move(temporaryPath, finalPath, { noOverwrite: true });
  }

  async function serviceRequest(paths, requestPath) {
    let request;
    try {
      request = JSON.parse(await IOUtils.readUTF8(requestPath));
      if (!/^[0-9a-f-]{36}$/.test(request.id)) {
        throw new Error("invalid request id");
      }
      if (!Number.isSafeInteger(request.targetBytes) || request.targetBytes <= 0) {
        throw new Error("targetBytes must be a positive integer");
      }

      const minInactiveMs = Number.isSafeInteger(request.minInactiveMs)
        ? Math.max(0, request.minInactiveMs)
        : 0;
      const baseline = await availableMemory();
      let estimatedBytes = 0;
      let observedBytes = 0;
      let unloadedTabs = 0;

      while (
        estimatedBytes < request.targetBytes &&
        observedBytes < request.targetBytes &&
        unloadedTabs < 100
      ) {
        const result = await unloadOne(minInactiveMs);
        if (!result) {
          break;
        }

        unloadedTabs += 1;
        estimatedBytes += result.estimatedBytes;
        await sleep(400);
        observedBytes = Math.max(0, (await availableMemory()) - baseline);
      }

      const reachedTarget =
        estimatedBytes >= request.targetBytes || observedBytes >= request.targetBytes;
      await writeResponse(paths, request.id, {
        id: request.id,
        reachedTarget,
        targetBytes: request.targetBytes,
        unloadedTabs,
        estimatedBytes,
        observedBytes,
      });
    } catch (error) {
      log(`request failed: ${error}`);
      if (request && /^[0-9a-f-]{36}$/.test(request.id)) {
        await writeResponse(paths, request.id, {
          id: request.id,
          reachedTarget: false,
          error: String(error),
        });
      }
    } finally {
      await IOUtils.remove(requestPath, { ignoreAbsent: true });
    }
  }

  const controller = {
    busy: false,
    underPressure: false,
    timer: null,
    paths: null,

    async tick() {
      if (this.busy) {
        return;
      }
      this.busy = true;

      try {
        const request = await claimRequest(this.paths);
        if (request) {
          await serviceRequest(this.paths, request);
          return;
        }

        if (!prefBool("enabled")) {
          this.underPressure = false;
          return;
        }

        const available = await availableMemory();
        const low = prefInt("lowAvailableMiB") * MiB;
        const high = prefInt("highAvailableMiB") * MiB;
        if (high <= low) {
          throw new Error("highAvailableMiB must be greater than lowAvailableMiB");
        }

        if (!this.underPressure && available <= low) {
          this.underPressure = true;
          log(`memory pressure entered at ${Math.round(available / MiB)} MiB available`);
        } else if (this.underPressure && available >= high) {
          this.underPressure = false;
          log(`memory pressure cleared at ${Math.round(available / MiB)} MiB available`);
        }

        if (this.underPressure) {
          await unloadOne(prefInt("minInactiveMs"));
        }
      } catch (error) {
        log(`poll failed: ${error}`);
      } finally {
        this.busy = false;
      }
    },

    async start() {
      try {
        this.paths = runtimePaths();
        await ensureRuntimeDirectories(this.paths);
        const interval = Math.max(250, prefInt("pollIntervalMs"));
        this.timer = Cc["@mozilla.org/timer;1"].createInstance(Ci.nsITimer);
        this.timer.initWithCallback(
          () => this.tick(),
          interval,
          Ci.nsITimer.TYPE_REPEATING_SLACK
        );
        log(`started; polling every ${interval} ms`);
        await this.tick();
      } catch (error) {
        log(`startup failed: ${error}`);
      }
    },
  };

  controller.start();
})();
