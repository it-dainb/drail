#!/usr/bin/env node

"use strict";

const fs = require("fs");
const path = require("path");

const repoRoot = path.join(__dirname, "..");
const cargoTomlPath = path.join(repoRoot, "Cargo.toml");
const npmPackagePath = path.join(repoRoot, "npm", "package.json");

function readCargoVersion() {
  const cargoToml = fs.readFileSync(cargoTomlPath, "utf8");
  const packageSection = cargoToml.match(/\[package\]([\s\S]*?)(?:\n\[|$)/);

  if (!packageSection) {
    throw new Error(`Could not find [package] section in ${cargoTomlPath}`);
  }

  const versionMatch = packageSection[1].match(/^version\s*=\s*"([^"]+)"/m);

  if (!versionMatch) {
    throw new Error(`Could not find package version in ${cargoTomlPath}`);
  }

  return versionMatch[1];
}

function syncNpmVersion(version) {
  const packageJson = JSON.parse(fs.readFileSync(npmPackagePath, "utf8"));

  if (packageJson.version === version) {
    return false;
  }

  packageJson.version = version;
  fs.writeFileSync(npmPackagePath, `${JSON.stringify(packageJson, null, 2)}\n`);
  return true;
}

function main() {
  const version = readCargoVersion();

  if (process.argv.includes("--print")) {
    process.stdout.write(`${version}\n`);
    return;
  }

  const changed = syncNpmVersion(version);
  const action = changed ? "updated" : "already up to date";
  process.stdout.write(`npm/package.json ${action} to ${version}\n`);
}

main();
