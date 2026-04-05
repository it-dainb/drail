#!/usr/bin/env node

"use strict";

const https = require("https");
const http = require("http");
const fs = require("fs");
const path = require("path");
const { execFileSync, spawn } = require("child_process");

const PLATFORM_MAP = {
  "linux-x64": "x86_64-unknown-linux-musl",
  "linux-arm64": "aarch64-unknown-linux-musl",
  "win32-x64": "x86_64-pc-windows-msvc",
};

const key = `${process.platform}-${process.arch}`;
const target = PLATFORM_MAP[key];

if (!target) {
  console.error(`drail: unsupported platform ${key}`);
  console.error(`Supported: ${Object.keys(PLATFORM_MAP).join(", ")}`);
  process.exit(1);
}

const version = require("./package.json").version;
const isWindows = process.platform === "win32";
const ext = isWindows ? "zip" : "tar.gz";
const binName = isWindows ? "drail.exe" : "drail";
const url = `https://github.com/it-dainb/drail/releases/download/v${version}/drail-${target}.${ext}`;

const binDir = path.join(__dirname, "bin");
const binPath = path.join(binDir, binName);

if (fs.existsSync(binPath)) {
  verifyBinary();
  maybeInstallSkill();
  console.log("drail: installed successfully");
  process.exit(0);
}

fs.mkdirSync(binDir, { recursive: true });

console.log(`drail: downloading ${target} binary...`);

function follow(nextUrl, callback) {
  const mod = nextUrl.startsWith("https") ? https : http;
  mod.get(nextUrl, { headers: { "User-Agent": "drail-npm" } }, (res) => {
    if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
      follow(res.headers.location, callback);
    } else if (res.statusCode !== 200) {
      console.error(`drail: download failed (HTTP ${res.statusCode})`);
      console.error(`URL: ${nextUrl}`);
      console.error("Install manually: cargo install drail");
      process.exit(1);
    } else {
      callback(res);
    }
  }).on("error", (err) => {
    console.error(`drail: download failed: ${err.message}`);
    console.error("Install manually: cargo install drail");
    process.exit(1);
  });
}

function finishInstall() {
  verifyBinary();
  maybeInstallSkill();
  console.log("drail: installed successfully");
}

function verifyBinary() {
  try {
    const versionText = execFileSync(binPath, ["--version"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
    console.log(`drail: verified CLI (${versionText})`);
  } catch (err) {
    console.error("drail: installed binary failed verification");
    console.error(err.stderr ? String(err.stderr) : err.message);
    process.exit(1);
  }
}

function maybeInstallSkill() {
  if (!isGlobalInstall()) {
    console.log("drail: skipping skill install for non-global npm install");
    return;
  }

  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    console.log("drail: skipping skill prompt in non-interactive install");
    return;
  }

  try {
    execFileSync(binPath, ["install-skill"], { stdio: "inherit" });
  } catch (err) {
    process.exit(err.status ?? 1);
  }
}

function isGlobalInstall() {
  return process.env.npm_config_global === "true" || process.env.npm_config_location === "global";
}

follow(url, (res) => {
  if (isWindows) {
    const tmpZip = path.join(binDir, "drail.zip");
    const out = fs.createWriteStream(tmpZip);
    res.pipe(out);
    out.on("finish", () => {
      out.close();
      try {
        execFileSync("tar", ["-xf", tmpZip, "-C", binDir], { stdio: "ignore" });
        fs.unlinkSync(tmpZip);
        finishInstall();
      } catch {
        console.error("drail: failed to extract. Install manually: cargo install drail");
        process.exit(1);
      }
    });
  } else {
    const tar = spawn("tar", ["xz", "-C", binDir], {
      stdio: ["pipe", "inherit", "inherit"],
    });
    res.pipe(tar.stdin);
    tar.on("close", (code) => {
      if (code !== 0) {
        console.error("drail: failed to extract. Install manually: cargo install drail");
        process.exit(1);
      }
      fs.chmodSync(binPath, 0o755);
      finishInstall();
    });
  }
});
