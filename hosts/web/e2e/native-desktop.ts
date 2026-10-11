import { test as base, expect, chromium, type BrowserContext, type Page } from "@playwright/test";
import { execFile, spawn, type ChildProcess } from "node:child_process";
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const exec = promisify(execFile);
const controls = fileURLToPath(new URL("native-controls.py", import.meta.url));

function firstLine(child: ChildProcess): Promise<string> {
  return new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", code => reject(new Error(`Desktop service exited before startup: ${code}`)));
    child.stdout!.once("data", data => resolve(String(data).trim().split("\n")[0]));
  });
}

interface Desktop {
  page: Page;
  notes: string;
  chooseFolder(path?: string): Promise<void>;
  allow(name: "Allow" | "Allow this time" | "Don't allow"): Promise<void>;
  restart(): Promise<Page>;
}

// Playwright owns browser actions and recording. Xvfb, D-Bus, Openbox and
// AT-SPI provide an isolated real Linux desktop for the OS-owned chooser and
// Chrome permission prompts. No File System Access or application API changes.
export const test = base.extend<{ desktop: Desktop }>({
  desktop: async ({ baseURL }, use, info) => {
    const profile = await mkdtemp(join(tmpdir(), "math-notes-browser-"));
    const notes = info.outputPath("notes");
    await mkdir(notes, { recursive: true });
    const services: ChildProcess[] = [];
    let context: BrowserContext | undefined;
    try {
      const display = spawn("Xvfb", ["-displayfd", "1", "-screen", "0", "1280x1024x24", "-nolisten", "tcp", "-ac"],
        { stdio: ["ignore", "pipe", "inherit"] });
      services.push(display);
      const env = { ...process.env, DISPLAY: `:${await firstLine(display)}`, GDK_BACKEND: "x11",
        GSK_RENDERER: "cairo", GTK_USE_PORTAL: "0", ACCESSIBILITY_ENABLED: "1" };
      const bus = spawn("dbus-daemon", ["--session", "--nofork", "--print-address=1"],
        { env, stdio: ["ignore", "pipe", "inherit"] });
      services.push(bus);
      const desktopEnv = { ...env, DBUS_SESSION_BUS_ADDRESS: await firstLine(bus) };
      const reply = await exec("gdbus", ["call", "--session", "--dest", "org.a11y.Bus", "--object-path", "/org/a11y/bus",
        "--method", "org.a11y.Bus.GetAddress"], { env: desktopEnv });
      const address = /'([^']+)'/.exec(reply.stdout)?.[1];
      if (!address) throw new Error(`AT-SPI did not return its bus address: ${reply.stdout}`);
      const nativeEnv = { ...desktopEnv, AT_SPI_BUS_ADDRESS: address };
      const wm = spawn("openbox", ["--config-file", process.env.MATH_NOTES_OPENBOX_CONFIG ?? "/etc/xdg/openbox/rc.xml", "--sm-disable"],
        { env: nativeEnv, stdio: ["ignore", "ignore", "inherit"] });
      services.push(wm);
      await expect.poll(async () => (await exec("xprop", ["-root", "_NET_SUPPORTING_WM_CHECK"], { env: nativeEnv })).stdout)
        .toContain("window id");
      const input = (...args: string[]) => exec("xdotool", args, { env: nativeEnv, timeout: 10_000 });
      const open = async () => {
        context = await chromium.launchPersistentContext(profile, {
          headless: false, env: nativeEnv, baseURL, viewport: { width: 1280, height: 900 },
          args: ["--force-renderer-accessibility"],
        });
        context.setDefaultTimeout(30_000);
        const page = context.pages()[0];
        await page.goto(baseURL!);
        return page;
      };
      const close = async () => {
        if (!context) return;
        await context.close();
        context = undefined;
      };
      const desktop: Desktop = {
        page: await open(), notes,
        async allow(name) {
          const locate = async () => JSON.parse((await exec("/usr/bin/python3", [controls, name],
            { env: nativeEnv, timeout: 10_000 })).stdout) as [number, number] | null;
          await expect.poll(locate, { timeout: 10_000 }).not.toBeNull();
          const windows = await input("search", "--onlyvisible", "--name", "Math Notes.*Chrome");
          await input("windowactivate", "--sync", windows.stdout.trim().split("\n")[0]);
          // Chromium InputEventActivationProtector rejects input within the
          // platform double-click interval after activation. Locate again
          // afterwards, since activation can reposition a native bubble.
          await new Promise(resolve => setTimeout(resolve, 600));
          const point = await locate();
          if (!point) throw new Error(`Native permission button disappeared: ${name}`);
          await input("mousemove", "--sync", String(point[0]), String(point[1]), "click", "1");
          await expect.poll(locate, { timeout: 10_000 }).toBeNull();
        },
        async chooseFolder(path = notes) {
          await desktop.page.getByRole("button", { name: "Choose notes folder", exact: true }).click();
          const dialog = await input("search", "--sync", "--onlyvisible", "--name", "Select where this site can save changes");
          await input("windowfocus", "--sync", dialog.stdout.trim().split("\n")[0]);
          await exec("import", ["-window", "root", info.outputPath("folder-chooser.png")], { env: nativeEnv });
          await input("key", "--clearmodifiers", "ctrl+l");
          await input("type", "--clearmodifiers", "--delay", "1", path);
          await input("key", "--clearmodifiers", "Return");
          await desktop.allow("Allow");
        },
        async restart() {
          await close();
          desktop.page = await open();
          return desktop.page;
        },
      };
      await use(desktop);
      await close();
    } finally {
      try {
        if (context) {
          await context.pages()[0]?.screenshot({ path: info.outputPath("desktop-final.png") });
          await context.close();
        }
      } finally {
        for (const service of services.reverse()) service.kill();
        await rm(profile, { recursive: true, force: true });
      }
    }
  },
});

export { expect };
