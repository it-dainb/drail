use std::io::{self, IsTerminal};

use serde_json::{json, Map, Value};

use crate::cli::args::InstallSkillArgs;
use crate::commands::install_helpers::{
    self, detect_targets, detected_label, install_global_config, install_skill_files,
    select_targets, verify_global_config, verify_skill_files, Detection, Selection,
};
use crate::error::DrailError;
use crate::output::CommandOutput;

pub fn run(args: &InstallSkillArgs) -> Result<CommandOutput, DrailError> {
    let detection = detect_targets();
    let selection = match args.target {
        Some(target) => select_targets(target, &detection),
        None if io::stdin().is_terminal() && io::stdout().is_terminal() => {
            install_helpers::prompt_for_targets(&detection, "install the drail skill")?
        }
        None => Selection::skipped(
            "Non-interactive shell; rerun `drail install-skill` in a terminal to choose skill targets.",
        ),
    };

    let mut installed = Vec::new();
    for target in &selection.targets {
        install_skill_files(target)?;
        verify_skill_files(target)?;
        install_global_config(&target.global_config_path)?;
        verify_global_config(&target.global_config_path)?;
        installed.push(json!({
            "target": target.name,
            "path": target.path.display().to_string(),
            "global_config": target.global_config_path.display().to_string(),
            "verified": true,
        }));
    }

    let note = if selection.targets.is_empty() {
        selection.note.clone()
    } else {
        format!(
            "Installed skill for {}.",
            selection.selected_names().join(" and ")
        )
    };

    let mut output = CommandOutput::with_parts(
        "install-skill",
        render_text(&detection, &selection, &note),
        json!({
            "detected": detection.detected_names(),
            "selected": selection.selected_names(),
            "installed": installed,
            "skipped": selection.targets.is_empty(),
        }),
        Vec::new(),
        true,
    );
    output.meta = meta_for_selection(&detection, &selection);
    Ok(output)
}

fn render_text(detection: &Detection, selection: &Selection, note: &str) -> String {
    use std::fmt::Write as _;
    let mut text = format!("Detected tooling: {}\n{note}", detected_label(detection),);

    if selection.targets.is_empty() {
        return text;
    }

    text.push_str("\nVerified skill targets:");
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

fn meta_for_selection(detection: &Detection, selection: &Selection) -> Map<String, Value> {
    let mut meta = Map::new();
    meta.insert("detected".into(), json!(detection.detected_names()));
    meta.insert("installed".into(), json!(selection.selected_names()));
    meta.insert("verified".into(), json!(!selection.targets.is_empty()));
    meta.insert("stability".into(), json!("high"));
    meta.insert("noise".into(), json!("low"));
    meta
}
