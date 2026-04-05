use std::env;
use std::fs;
use std::io::{self, Write as _};
use std::path::{Path, PathBuf};

use crate::cli::args::InstallSkillTarget;
use crate::error::DrailError;

pub const SKILL_MD: &str = include_str!("../../skill/SKILL.md");
pub const COMMANDS_REFERENCE_MD: &str = include_str!("../../skill/references/commands-reference.md");
pub const OUTPUT_CONTRACT_MD: &str = include_str!("../../skill/references/output-contract.md");
pub const WORKFLOW_PATTERNS_MD: &str =
    include_str!("../../skill/references/workflow-patterns.md");
pub const AGENTS_GUIDE_MD: &str = include_str!("../../skill/AGENTS_GUIDE.md");

pub const DRAIL_VERSION: &str = env!("CARGO_PKG_VERSION");

pub const DRAIL_START: &str = "<!-- DRAIL:START -->";
pub const DRAIL_END: &str = "<!-- DRAIL:END -->";
pub const DRAIL_VERSION_PREFIX: &str = "<!-- DRAIL:VERSION:";
pub const DRAIL_VERSION_SUFFIX: &str = " -->";

pub const CLAUDE_TARGET: &str = "claude";
pub const OPENCODE_TARGET: &str = "opencode";

pub struct Detection {
    pub claude: Option<PathBuf>,
    pub opencode: Option<PathBuf>,
}

impl Detection {
    #[must_use] 
    pub fn detected_names(&self) -> Vec<&'static str> {
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

pub struct Selection {
    pub targets: Vec<InstallTarget>,
    pub note: String,
}

impl Selection {
    pub fn skipped(note: impl Into<String>) -> Self {
        Self {
            targets: Vec::new(),
            note: note.into(),
        }
    }

    #[must_use] 
    pub fn selected_names(&self) -> Vec<&'static str> {
        self.targets.iter().map(|target| target.name).collect()
    }
}

#[derive(Clone)]
pub struct InstallTarget {
    pub name: &'static str,
    pub path: PathBuf,
    pub global_config_path: PathBuf,
}

#[must_use] 
pub fn detect_targets() -> Detection {
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

pub fn home_dir() -> Option<PathBuf> {
    env::var_os("HOME").map(PathBuf::from)
}

pub fn config_home() -> Option<PathBuf> {
    env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| home_dir().map(|home| home.join(".config")))
}

#[must_use] 
pub fn select_targets(target: InstallSkillTarget, detection: &Detection) -> Selection {
    match target {
        InstallSkillTarget::Claude => Selection {
            targets: vec![claude_target()],
            note: String::new(),
        },
        InstallSkillTarget::Opencode => Selection {
            targets: vec![opencode_target()],
            note: String::new(),
        },
        InstallSkillTarget::Both => Selection {
            targets: vec![claude_target(), opencode_target()],
            note: String::new(),
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
                Selection::skipped(
                    "No Claude Code or OpenCode config directory detected.",
                )
            } else {
                Selection {
                    targets,
                    note: String::new(),
                }
            }
        }
        InstallSkillTarget::Skip => Selection::skipped("Skipped."),
    }
}

#[must_use] 
pub fn claude_target() -> InstallTarget {
    let home = home_dir().unwrap_or_else(|| PathBuf::from("~"));
    let path = home.join(".claude").join("skills").join("drail");
    let global_config_path = home.join(".claude").join("CLAUDE.md");
    InstallTarget {
        name: CLAUDE_TARGET,
        path,
        global_config_path,
    }
}

#[must_use] 
pub fn opencode_target() -> InstallTarget {
    let config = config_home().unwrap_or_else(|| PathBuf::from("~/.config"));
    let path = config.join("opencode").join("skills").join("drail");
    let global_config_path = config.join("opencode").join("AGENTS.md");
    InstallTarget {
        name: OPENCODE_TARGET,
        path,
        global_config_path,
    }
}

struct PromptOption {
    label: &'static str,
    target: InstallSkillTarget,
}

pub fn prompt_for_targets(
    detection: &Detection,
    action_label: &str,
) -> Result<Selection, DrailError> {
    eprintln!(
        "drail: detected [{}]",
        detected_label(detection)
    );
    eprintln!("drail: choose targets to {action_label}:");

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
        return Ok(Selection::skipped("Invalid selection; skipped."));
    };

    Ok(options.get(index).map_or_else(
        || Selection::skipped("Invalid selection; skipped."),
        |option| select_targets(option.target, detection),
    ))
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
        label: "Skip",
        target: InstallSkillTarget::Skip,
    });
    options
}

#[must_use] 
pub fn detected_label(detection: &Detection) -> String {
    let names = detection.detected_names();
    if names.is_empty() {
        "none".into()
    } else {
        names.join(", ")
    }
}

// --- File I/O helpers ---

pub fn write_file(path: &Path, content: &str) -> Result<(), DrailError> {
    fs::write(path, content).map_err(|source| DrailError::IoError {
        path: path.to_path_buf(),
        source,
    })
}

pub fn verify_file(path: &Path, expected: &str) -> Result<(), DrailError> {
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

// --- Skill install/uninstall ---

pub fn install_skill_files(target: &InstallTarget) -> Result<(), DrailError> {
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

pub fn verify_skill_files(target: &InstallTarget) -> Result<(), DrailError> {
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

pub fn remove_skill_files(target: &InstallTarget) -> Result<bool, DrailError> {
    if !target.path.exists() {
        return Ok(false);
    }
    fs::remove_dir_all(&target.path).map_err(|source| DrailError::IoError {
        path: target.path.clone(),
        source,
    })?;
    Ok(true)
}

// --- DRAIL block management ---

#[must_use] 
pub fn build_drail_block(content: &str, version: &str) -> String {
    format!(
        "{}\n{}{}{}\n\n{}\n\n{}",
        DRAIL_START,
        DRAIL_VERSION_PREFIX,
        version,
        DRAIL_VERSION_SUFFIX,
        content.trim(),
        DRAIL_END,
    )
}

/// Returns `Some((start_byte, end_byte, existing_version))` if a DRAIL block is found.
#[must_use] 
pub fn find_drail_block(text: &str) -> Option<(usize, usize, String)> {
    let start = text.find(DRAIL_START)?;
    let end_marker = text[start..].find(DRAIL_END)?;
    let end = start + end_marker + DRAIL_END.len();

    let block = &text[start..end];
    let version = block
        .find(DRAIL_VERSION_PREFIX)
        .and_then(|vstart| {
            let after = &block[vstart + DRAIL_VERSION_PREFIX.len()..];
            after
                .find(DRAIL_VERSION_SUFFIX)
                .map(|vend| after[..vend].to_string())
        })
        .unwrap_or_default();

    Some((start, end, version))
}

pub fn install_global_config(path: &Path) -> Result<(), DrailError> {
    let block = build_drail_block(AGENTS_GUIDE_MD, DRAIL_VERSION);

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|source| DrailError::IoError {
            path: parent.to_path_buf(),
            source,
        })?;
    }

    let content = if path.exists() {
        let existing = fs::read_to_string(path).map_err(|source| DrailError::IoError {
            path: path.to_path_buf(),
            source,
        })?;

        if let Some((start, end, ref existing_version)) = find_drail_block(&existing) {
            if existing_version == DRAIL_VERSION {
                return Ok(());
            }
            format!("{}{}{}", &existing[..start], block, &existing[end..])
        } else if existing.ends_with('\n') {
            format!("{existing}\n{block}\n")
        } else {
            format!("{existing}\n\n{block}\n")
        }
    } else {
        format!("{block}\n")
    };

    write_file(path, &content)
}

pub fn verify_global_config(path: &Path) -> Result<(), DrailError> {
    let content = fs::read_to_string(path).map_err(|source| DrailError::IoError {
        path: path.to_path_buf(),
        source,
    })?;

    match find_drail_block(&content) {
        Some((_, _, ref version)) if version == DRAIL_VERSION => Ok(()),
        Some((_, _, ref version)) => Err(DrailError::ParseError {
            path: path.to_path_buf(),
            reason: format!(
                "DRAIL block version mismatch: expected {DRAIL_VERSION}, found {version}",
            ),
        }),
        None => Err(DrailError::ParseError {
            path: path.to_path_buf(),
            reason: "DRAIL block not found in global config".into(),
        }),
    }
}

pub fn remove_global_config(path: &Path) -> Result<bool, DrailError> {
    if !path.exists() {
        return Ok(false);
    }

    let existing = fs::read_to_string(path).map_err(|source| DrailError::IoError {
        path: path.to_path_buf(),
        source,
    })?;

    let Some((start, end, _)) = find_drail_block(&existing) else {
        return Ok(false);
    };

    // Remove the block and clean up surrounding whitespace
    let before = existing[..start].trim_end_matches('\n');
    let after = existing[end..].trim_start_matches('\n');

    let content = match (before.is_empty(), after.is_empty()) {
        (true, true) => {
            // File was only the DRAIL block — remove the file
            fs::remove_file(path).map_err(|source| DrailError::IoError {
                path: path.to_path_buf(),
                source,
            })?;
            return Ok(true);
        }
        (true, false) => format!("{after}\n"),
        (false, true) => format!("{before}\n"),
        (false, false) => format!("{before}\n\n{after}\n"),
    };

    write_file(path, &content)?;
    Ok(true)
}

// --- Binary path helpers ---

#[must_use] 
pub fn current_binary_path() -> Option<PathBuf> {
    env::current_exe().ok()
}

#[must_use] 
pub fn default_binary_path() -> PathBuf {
    home_dir()
        .unwrap_or_else(|| PathBuf::from("~"))
        .join(".local")
        .join("bin")
        .join("drail")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_path(label: &str) -> PathBuf {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        env::temp_dir().join(format!(
            "drail-helpers-test-{label}-{}-{nanos}",
            std::process::id()
        ))
    }

    #[test]
    fn build_drail_block_format() {
        let block = build_drail_block("Hello world", "1.2.3");
        assert!(block.starts_with(DRAIL_START));
        assert!(block.ends_with(DRAIL_END));
        assert!(block.contains("<!-- DRAIL:VERSION:1.2.3 -->"));
        assert!(block.contains("Hello world"));
    }

    #[test]
    fn find_drail_block_parses_existing() {
        let text = "some content\n<!-- DRAIL:START -->\n<!-- DRAIL:VERSION:0.0.5 -->\n\nstuff\n\n<!-- DRAIL:END -->\nmore content";
        let (start, end, version) = find_drail_block(text).expect("block should be found");
        assert_eq!(version, "0.0.5");
        assert!(start > 0);
        assert!(end > start);
        assert_eq!(&text[end..], "\nmore content");
    }

    #[test]
    fn find_drail_block_returns_none_when_missing() {
        assert!(find_drail_block("no markers here").is_none());
        assert!(find_drail_block("<!-- DRAIL:START --> but no end").is_none());
    }

    #[test]
    fn install_global_config_creates_new_file() {
        let dir = temp_path("new-file");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("CLAUDE.md");

        install_global_config(&path).unwrap();
        let content = fs::read_to_string(&path).unwrap();
        assert!(content.contains(DRAIL_START));
        assert!(content.contains(DRAIL_END));
        assert!(content.contains(&format!(
            "{}{}{}", DRAIL_VERSION_PREFIX, DRAIL_VERSION, DRAIL_VERSION_SUFFIX
        )));

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn install_global_config_appends_to_existing() {
        let dir = temp_path("append");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("CLAUDE.md");
        fs::write(&path, "# Existing content\n\nSome rules here.\n").unwrap();

        install_global_config(&path).unwrap();
        let content = fs::read_to_string(&path).unwrap();
        assert!(content.starts_with("# Existing content"));
        assert!(content.contains(DRAIL_START));
        assert!(content.contains(DRAIL_END));

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn install_global_config_updates_older_version() {
        let dir = temp_path("update");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("CLAUDE.md");

        let old_block = build_drail_block("old content", "0.0.1");
        fs::write(&path, format!("# My config\n\n{}\n\n# Other stuff\n", old_block)).unwrap();

        install_global_config(&path).unwrap();
        let content = fs::read_to_string(&path).unwrap();

        assert!(!content.contains("0.0.1"));
        assert!(content.contains(&format!(
            "{}{}{}", DRAIL_VERSION_PREFIX, DRAIL_VERSION, DRAIL_VERSION_SUFFIX
        )));
        assert!(content.starts_with("# My config"));
        assert!(content.contains("# Other stuff"));

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn install_global_config_skips_same_version() {
        let dir = temp_path("same-version");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("CLAUDE.md");

        let block = build_drail_block(AGENTS_GUIDE_MD, DRAIL_VERSION);
        let original = format!("# Config\n\n{}\n", block);
        fs::write(&path, &original).unwrap();

        install_global_config(&path).unwrap();
        let content = fs::read_to_string(&path).unwrap();
        assert_eq!(content, original);

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn install_global_config_creates_parent_dirs() {
        let dir = temp_path("parent-dirs");
        let path = dir.join("deep").join("nested").join("AGENTS.md");

        install_global_config(&path).unwrap();
        assert!(path.exists());
        let content = fs::read_to_string(&path).unwrap();
        assert!(content.contains(DRAIL_START));

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn verify_global_config_passes_current_version() {
        let dir = temp_path("verify-pass");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("CLAUDE.md");

        install_global_config(&path).unwrap();
        verify_global_config(&path).unwrap();

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn verify_global_config_fails_wrong_version() {
        let dir = temp_path("verify-fail");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("CLAUDE.md");

        let block = build_drail_block("content", "0.0.0");
        fs::write(&path, block).unwrap();

        let result = verify_global_config(&path);
        assert!(result.is_err());

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn remove_global_config_removes_block_from_middle() {
        let dir = temp_path("remove-middle");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("CLAUDE.md");

        let block = build_drail_block("content", "0.0.5");
        fs::write(&path, format!("# Before\n\n{block}\n\n# After\n")).unwrap();

        let removed = remove_global_config(&path).unwrap();
        assert!(removed);
        let content = fs::read_to_string(&path).unwrap();
        assert!(!content.contains(DRAIL_START));
        assert!(content.contains("# Before"));
        assert!(content.contains("# After"));

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn remove_global_config_deletes_file_when_only_block() {
        let dir = temp_path("remove-only");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("AGENTS.md");

        let block = build_drail_block("content", "0.0.5");
        fs::write(&path, format!("{block}\n")).unwrap();

        let removed = remove_global_config(&path).unwrap();
        assert!(removed);
        assert!(!path.exists());

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn remove_global_config_returns_false_when_no_block() {
        let dir = temp_path("remove-none");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("CLAUDE.md");
        fs::write(&path, "# No drail block here\n").unwrap();

        let removed = remove_global_config(&path).unwrap();
        assert!(!removed);

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn remove_global_config_returns_false_when_file_missing() {
        let dir = temp_path("remove-missing");
        let path = dir.join("nonexistent.md");

        let removed = remove_global_config(&path).unwrap();
        assert!(!removed);
    }

    #[test]
    fn remove_skill_files_returns_false_when_missing() {
        let target = InstallTarget {
            name: "test",
            path: PathBuf::from("/tmp/drail-test-nonexistent-skill-dir"),
            global_config_path: PathBuf::from("/tmp/unused"),
        };
        let removed = remove_skill_files(&target).unwrap();
        assert!(!removed);
    }

    #[test]
    fn remove_skill_files_removes_existing_dir() {
        let dir = temp_path("remove-skill");
        let skill_path = dir.join("skills").join("drail");
        fs::create_dir_all(skill_path.join("references")).unwrap();
        fs::write(skill_path.join("SKILL.md"), "test").unwrap();

        let target = InstallTarget {
            name: "test",
            path: skill_path.clone(),
            global_config_path: PathBuf::from("/tmp/unused"),
        };
        let removed = remove_skill_files(&target).unwrap();
        assert!(removed);
        assert!(!skill_path.exists());

        fs::remove_dir_all(&dir).ok();
    }
}
