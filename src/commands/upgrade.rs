use std::io::{self, IsTerminal};
use std::process;

use serde_json::{json, Map, Value};

use crate::cli::args::UpgradeArgs;
use crate::commands::install_helpers::{
    self, current_binary_path, default_binary_path, detect_targets, detected_label,
    install_global_config, install_skill_files, select_targets, verify_global_config,
    verify_skill_files, Detection, Selection, DRAIL_VERSION,
};
use crate::error::DrailError;
use crate::output::CommandOutput;

pub fn run(args: &UpgradeArgs) -> Result<CommandOutput, DrailError> {
    let bin_result = upgrade_binary()?;
    let new_version = bin_result.new_version.clone();

    let detection = detect_targets();
    let selection = match args.target {
        Some(target) => select_targets(target, &detection),
        None if io::stdin().is_terminal() && io::stdout().is_terminal() => {
            install_helpers::prompt_for_targets(&detection, "upgrade drail skill for")?
        }
        None => {
            // Non-interactive: upgrade detected targets
            select_targets(
                crate::cli::args::InstallSkillTarget::Detected,
                &detection,
            )
        }
    };

    let mut upgraded = Vec::new();
    for target in &selection.targets {
        install_skill_files(target)?;
        verify_skill_files(target)?;
        install_global_config(&target.global_config_path)?;
        verify_global_config(&target.global_config_path)?;
        upgraded.push(json!({
            "target": target.name,
            "path": target.path.display().to_string(),
            "global_config": target.global_config_path.display().to_string(),
            "verified": true,
        }));
    }

    let mut output = CommandOutput::with_parts(
        "upgrade",
        render_text(&detection, &selection, &bin_result, &new_version),
        json!({
            "previous_version": DRAIL_VERSION,
            "new_version": new_version,
            "binary_upgraded": bin_result.upgraded,
            "method": bin_result.method,
            "detected": detection.detected_names(),
            "selected": selection.selected_names(),
            "upgraded": upgraded,
        }),
        Vec::new(),
        true,
    );
    output.meta = meta_for_upgrade(&detection, &selection, &bin_result);
    Ok(output)
}

struct BinaryUpgradeResult {
    upgraded: bool,
    method: &'static str,
    new_version: String,
}

fn upgrade_binary() -> Result<BinaryUpgradeResult, DrailError> {
    // Try cargo install first (works for cargo-installed binaries)
    if try_cargo_install()? {
        let version = get_new_version()?;
        return Ok(BinaryUpgradeResult {
            upgraded: true,
            method: "cargo",
            new_version: version,
        });
    }

    // Try npm update (works for npm-installed binaries)
    if try_npm_update()? {
        let version = get_new_version()?;
        return Ok(BinaryUpgradeResult {
            upgraded: true,
            method: "npm",
            new_version: version,
        });
    }

    // No upgrade method available — just update skills with current version
    Ok(BinaryUpgradeResult {
        upgraded: false,
        method: "none",
        new_version: DRAIL_VERSION.to_string(),
    })
}

fn try_cargo_install() -> Result<bool, DrailError> {
    let status = process::Command::new("cargo")
        .args(["install", "drail"])
        .stdout(process::Stdio::inherit())
        .stderr(process::Stdio::inherit())
        .status();

    match status {
        Ok(s) if s.success() => Ok(true),
        Ok(_) | Err(_) => Ok(false),
    }
}

fn try_npm_update() -> Result<bool, DrailError> {
    let status = process::Command::new("npm")
        .args(["install", "-g", "drail@latest"])
        .stdout(process::Stdio::inherit())
        .stderr(process::Stdio::inherit())
        .status();

    match status {
        Ok(s) if s.success() => Ok(true),
        Ok(_) | Err(_) => Ok(false),
    }
}

fn get_new_version() -> Result<String, DrailError> {
    let bin_path = current_binary_path().unwrap_or_else(default_binary_path);

    let output = process::Command::new(&bin_path)
        .arg("--version")
        .output()
        .map_err(|source| DrailError::IoError {
            path: bin_path,
            source,
        })?;

    let version_text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    // Parse "drail X.Y.Z" -> "X.Y.Z"
    Ok(version_text
        .strip_prefix("drail ")
        .unwrap_or(&version_text)
        .to_string())
}

fn render_text(
    detection: &Detection,
    selection: &Selection,
    bin_result: &BinaryUpgradeResult,
    new_version: &str,
) -> String {
    use std::fmt::Write as _;
    let mut text = String::new();

    if bin_result.upgraded {
        let _ = write!(
            text,
            "Binary upgraded via {}: {} -> {new_version}",
            bin_result.method, DRAIL_VERSION
        );
    } else {
        let _ = write!(
            text,
            "Binary upgrade skipped (install via cargo or npm to enable). Current version: {DRAIL_VERSION}"
        );
    }

    let _ = write!(text, "\nDetected tooling: {}", detected_label(detection));

    if selection.targets.is_empty() {
        let _ = write!(text, "\n{}", selection.note);
        return text;
    }

    text.push_str("\nUpgraded skill targets:");
    for target in &selection.targets {
        let _ = write!(text, "\n- {}: {}", target.name, target.path.display());
        let _ = write!(
            text,
            "\n  global config: {}",
            target.global_config_path.display()
        );
    }
    text
}

fn meta_for_upgrade(
    detection: &Detection,
    selection: &Selection,
    bin_result: &BinaryUpgradeResult,
) -> Map<String, Value> {
    let mut meta = Map::new();
    meta.insert("detected".into(), json!(detection.detected_names()));
    meta.insert("upgraded".into(), json!(selection.selected_names()));
    meta.insert("binary_upgraded".into(), json!(bin_result.upgraded));
    meta.insert("method".into(), json!(bin_result.method));
    meta.insert("stability".into(), json!("high"));
    meta.insert("noise".into(), json!("low"));
    meta
}
