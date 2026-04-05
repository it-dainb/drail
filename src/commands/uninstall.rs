use std::fs;
use std::io::{self, IsTerminal};

use serde_json::{json, Map, Value};

use crate::cli::args::UninstallArgs;
use crate::commands::install_helpers::{
    self, current_binary_path, default_binary_path, detect_targets, detected_label,
    remove_global_config, remove_skill_files, select_targets, Detection, Selection,
};
use crate::error::DrailError;
use crate::output::CommandOutput;

pub fn run(args: &UninstallArgs) -> Result<CommandOutput, DrailError> {
    let detection = detect_targets();
    let selection = match args.target {
        Some(target) => select_targets(target, &detection),
        None if io::stdin().is_terminal() && io::stdout().is_terminal() => {
            install_helpers::prompt_for_targets(&detection, "uninstall drail from")?
        }
        None => Selection::skipped(
            "Non-interactive shell; rerun `drail uninstall` in a terminal to choose targets.",
        ),
    };

    let mut removed = Vec::new();
    for target in &selection.targets {
        let skill_removed = remove_skill_files(target)?;
        let config_removed = remove_global_config(&target.global_config_path)?;
        removed.push(json!({
            "target": target.name,
            "skill_removed": skill_removed,
            "global_config_removed": config_removed,
        }));
    }

    // Remove the binary itself if --bin is specified
    let bin_removed = if args.bin {
        remove_binary()?
    } else {
        false
    };

    let note = if selection.targets.is_empty() && !bin_removed {
        selection.note.clone()
    } else {
        let mut parts = Vec::new();
        if !selection.targets.is_empty() {
            parts.push(format!(
                "Removed drail skill and config from {}.",
                selection.selected_names().join(" and ")
            ));
        }
        if bin_removed {
            parts.push("Removed drail binary.".into());
        }
        parts.join(" ")
    };

    let mut output = CommandOutput::with_parts(
        "uninstall",
        render_text(&detection, &selection, &note, bin_removed),
        json!({
            "detected": detection.detected_names(),
            "selected": selection.selected_names(),
            "removed": removed,
            "bin_removed": bin_removed,
            "skipped": selection.targets.is_empty() && !bin_removed,
        }),
        Vec::new(),
        true,
    );
    output.meta = meta_for_result(&detection, &selection, bin_removed);
    Ok(output)
}

fn remove_binary() -> Result<bool, DrailError> {
    // Try current exe first, fall back to default path
    let bin_path = current_binary_path().unwrap_or_else(default_binary_path);

    if !bin_path.exists() {
        return Ok(false);
    }

    fs::remove_file(&bin_path).map_err(|source| DrailError::IoError {
        path: bin_path,
        source,
    })?;
    Ok(true)
}

fn render_text(
    detection: &Detection,
    selection: &Selection,
    note: &str,
    bin_removed: bool,
) -> String {
    use std::fmt::Write as _;
    let mut text = format!("Detected tooling: {}\n{note}", detected_label(detection));

    if !selection.targets.is_empty() {
        text.push_str("\nRemoved targets:");
        for target in &selection.targets {
            let _ = write!(text, "\n- {}: {}", target.name, target.path.display());
            let _ = write!(
                text,
                "\n  global config: {}",
                target.global_config_path.display()
            );
        }
    }

    if bin_removed {
        if let Some(bin) = current_binary_path() {
            let _ = write!(text, "\nRemoved binary: {}", bin.display());
        }
    }

    text
}

fn meta_for_result(
    detection: &Detection,
    selection: &Selection,
    bin_removed: bool,
) -> Map<String, Value> {
    let mut meta = Map::new();
    meta.insert("detected".into(), json!(detection.detected_names()));
    meta.insert("removed".into(), json!(selection.selected_names()));
    meta.insert("bin_removed".into(), json!(bin_removed));
    meta.insert("stability".into(), json!("high"));
    meta.insert("noise".into(), json!("low"));
    meta
}
