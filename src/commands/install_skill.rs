use std::env;
use std::fs;
use std::io::{self, IsTerminal, Write as _};
use std::path::{Path, PathBuf};

use serde_json::{json, Map, Value};

use crate::cli::args::{InstallSkillArgs, InstallSkillTarget};
use crate::error::DrailError;
use crate::output::CommandOutput;

const SKILL_MD: &str = include_str!("../../skill/SKILL.md");
const COMMANDS_REFERENCE_MD: &str = include_str!("../../skill/references/commands-reference.md");
const OUTPUT_CONTRACT_MD: &str = include_str!("../../skill/references/output-contract.md");
const WORKFLOW_PATTERNS_MD: &str = include_str!("../../skill/references/workflow-patterns.md");

const CLAUDE_TARGET: &str = "claude";
const OPENCODE_TARGET: &str = "opencode";

pub fn run(args: &InstallSkillArgs) -> Result<CommandOutput, DrailError> {
    let detection = detect_targets();
    let selection = match args.target {
        Some(target) => select_targets(target, &detection),
        None if io::stdin().is_terminal() && io::stdout().is_terminal() => prompt_for_targets(&detection)?,
        None => Selection::skipped("Non-interactive shell; rerun `drail install-skill` in a terminal to choose skill targets."),
    };

    let mut installed = Vec::new();
    for target in &selection.targets {
        install_target(target)?;
        verify_target(target)?;
        installed.push(json!({
            "target": target.name,
            "path": target.path.display().to_string(),
            "verified": true,
        }));
    }

    let mut output = CommandOutput::with_parts(
        "install-skill",
        render_text(&detection, &selection),
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

struct Detection {
    claude: Option<PathBuf>,
    opencode: Option<PathBuf>,
}

impl Detection {
    fn detected_names(&self) -> Vec<&'static str> {
        let mut names = Vec::new();
        if self.claude.is_some() {
            names.push(CLAUDE_TARGET);
        }
        if self.opencode.is_some() {
            names.push(OPENCODE_TARGET);
        }
        names
    }
}

struct Selection {
    targets: Vec<InstallTarget>,
    note: String,
}

impl Selection {
    fn skipped(note: impl Into<String>) -> Self {
        Self {
            targets: Vec::new(),
            note: note.into(),
        }
    }

    fn selected_names(&self) -> Vec<&'static str> {
        self.targets.iter().map(|target| target.name).collect()
    }
}

#[derive(Clone)]
struct InstallTarget {
    name: &'static str,
    path: PathBuf,
}

fn detect_targets() -> Detection {
    Detection {
        claude: detect_claude_path(),
        opencode: detect_opencode_path(),
    }
}

fn detect_claude_path() -> Option<PathBuf> {
    let home = home_dir()?;
    let root = home.join(".claude");
    root.exists().then(|| root.join("skills").join("drail"))
}

fn detect_opencode_path() -> Option<PathBuf> {
    let config_home = config_home()?;
    let root = config_home.join("opencode");
    root.exists().then(|| root.join("skills").join("drail"))
}

fn home_dir() -> Option<PathBuf> {
    env::var_os("HOME").map(PathBuf::from)
}

fn config_home() -> Option<PathBuf> {
    env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| home_dir().map(|home| home.join(".config")))
}

fn select_targets(target: InstallSkillTarget, detection: &Detection) -> Selection {
    match target {
        InstallSkillTarget::Claude => Selection {
            targets: vec![claude_target()],
            note: "Installed skill for Claude Code.".into(),
        },
        InstallSkillTarget::Opencode => Selection {
            targets: vec![opencode_target()],
            note: "Installed skill for OpenCode.".into(),
        },
        InstallSkillTarget::Both => Selection {
            targets: vec![claude_target(), opencode_target()],
            note: "Installed skill for Claude Code and OpenCode.".into(),
        },
        InstallSkillTarget::Detected => {
            let mut targets = Vec::new();
            if detection.claude.is_some() {
                targets.push(claude_target());
            }
            if detection.opencode.is_some() {
                targets.push(opencode_target());
            }

            if targets.is_empty() {
                Selection::skipped("No Claude Code or OpenCode config directory detected; skill installation skipped.")
            } else {
                Selection {
                    targets,
                    note: "Installed skill for detected tooling.".into(),
                }
            }
        }
        InstallSkillTarget::Skip => Selection::skipped("Skill installation skipped."),
    }
}

fn claude_target() -> InstallTarget {
    let path = home_dir()
        .unwrap_or_else(|| PathBuf::from("~"))
        .join(".claude")
        .join("skills")
        .join("drail");
    InstallTarget {
        name: CLAUDE_TARGET,
        path,
    }
}

fn opencode_target() -> InstallTarget {
    let path = config_home()
        .unwrap_or_else(|| PathBuf::from("~/.config"))
        .join("opencode")
        .join("skills")
        .join("drail");
    InstallTarget {
        name: OPENCODE_TARGET,
        path,
    }
}

fn prompt_for_targets(detection: &Detection) -> Result<Selection, DrailError> {
    eprintln!("drail: skill installer detected [{}]", detected_label(detection));
    eprintln!("drail: choose where to install the drail skill:");

    let options = prompt_options(detection);
    for (index, option) in options.iter().enumerate() {
        eprintln!("  {}. {}", index + 1, option.label);
    }
    eprint!("Enter choice [1-{}]: ", options.len());
    io::stderr().flush().map_err(|source| DrailError::IoError {
        path: PathBuf::from("stderr"),
        source,
    })?;

    let mut input = String::new();
    io::stdin()
        .read_line(&mut input)
        .map_err(|source| DrailError::IoError {
            path: PathBuf::from("stdin"),
            source,
        })?;

    let choice = input.trim().parse::<usize>().ok();
    let Some(index) = choice.and_then(|value| value.checked_sub(1)) else {
        return Ok(Selection::skipped("Invalid selection; skill installation skipped."));
    };

    Ok(options
        .get(index)
        .map(|option| select_targets(option.target, detection))
        .unwrap_or_else(|| Selection::skipped("Invalid selection; skill installation skipped.")))
}

struct PromptOption {
    label: &'static str,
    target: InstallSkillTarget,
}

fn prompt_options(detection: &Detection) -> Vec<PromptOption> {
    let mut options = Vec::new();
    if !detection.detected_names().is_empty() {
        options.push(PromptOption {
            label: "Detected apps",
            target: InstallSkillTarget::Detected,
        });
    }
    options.push(PromptOption {
        label: "Claude Code only",
        target: InstallSkillTarget::Claude,
    });
    options.push(PromptOption {
        label: "OpenCode only",
        target: InstallSkillTarget::Opencode,
    });
    options.push(PromptOption {
        label: "Both Claude Code and OpenCode",
        target: InstallSkillTarget::Both,
    });
    options.push(PromptOption {
        label: "Skip skill install",
        target: InstallSkillTarget::Skip,
    });
    options
}

fn detected_label(detection: &Detection) -> String {
    let names = detection.detected_names();
    if names.is_empty() {
        "none".into()
    } else {
        names.join(", ")
    }
}

fn install_target(target: &InstallTarget) -> Result<(), DrailError> {
    fs::create_dir_all(target.path.join("references")).map_err(|source| DrailError::IoError {
        path: target.path.clone(),
        source,
    })?;

    write_file(&target.path.join("SKILL.md"), SKILL_MD)?;
    write_file(
        &target.path.join("references/commands-reference.md"),
        COMMANDS_REFERENCE_MD,
    )?;
    write_file(
        &target.path.join("references/output-contract.md"),
        OUTPUT_CONTRACT_MD,
    )?;
    write_file(
        &target.path.join("references/workflow-patterns.md"),
        WORKFLOW_PATTERNS_MD,
    )?;
    Ok(())
}

fn write_file(path: &Path, content: &str) -> Result<(), DrailError> {
    fs::write(path, content).map_err(|source| DrailError::IoError {
        path: path.to_path_buf(),
        source,
    })
}

fn verify_target(target: &InstallTarget) -> Result<(), DrailError> {
    verify_file(&target.path.join("SKILL.md"), SKILL_MD)?;
    verify_file(
        &target.path.join("references/commands-reference.md"),
        COMMANDS_REFERENCE_MD,
    )?;
    verify_file(
        &target.path.join("references/output-contract.md"),
        OUTPUT_CONTRACT_MD,
    )?;
    verify_file(
        &target.path.join("references/workflow-patterns.md"),
        WORKFLOW_PATTERNS_MD,
    )?;
    Ok(())
}

fn verify_file(path: &Path, expected: &str) -> Result<(), DrailError> {
    let actual = fs::read_to_string(path).map_err(|source| DrailError::IoError {
        path: path.to_path_buf(),
        source,
    })?;
    if actual == expected {
        Ok(())
    } else {
        Err(DrailError::ParseError {
            path: path.to_path_buf(),
            reason: "installed skill content did not match embedded asset".into(),
        })
    }
}

fn render_text(detection: &Detection, selection: &Selection) -> String {
    let mut text = format!(
        "Detected tooling: {}\n{}",
        detected_label(detection),
        selection.note
    );

    if selection.targets.is_empty() {
        return text;
    }

    text.push_str("\nVerified skill targets:");
    for target in &selection.targets {
        text.push_str(&format!("\n- {}: {}", target.name, target.path.display()));
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
