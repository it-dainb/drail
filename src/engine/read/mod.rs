use std::path::Path;

use serde::Serialize;

use crate::cache::OutlineCache;
use crate::error::PatchError;
use crate::output::json::envelope::{Diagnostic, DiagnosticLevel};

#[derive(Debug, Clone)]
pub enum ReadSelector {
    Full,
    Lines { start: usize, end: usize },
    Heading(String),
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ReadSelectorData {
    Full,
    Lines { start: usize, end: usize },
    Heading { value: String },
}

#[derive(Debug, Clone, Serialize)]
pub struct ReadResultData {
    pub path: String,
    pub selector: ReadSelectorData,
    pub content: String,
}

#[derive(Debug, Clone)]
pub struct ReadCommandResult {
    pub data: ReadResultData,
    pub diagnostics: Vec<Diagnostic>,
}

pub fn run(
    path: &Path,
    selector: ReadSelector,
    full: bool,
    budget: Option<u64>,
) -> Result<ReadCommandResult, PatchError> {
    let cache = OutlineCache::new();

    let legacy_section = match &selector {
        ReadSelector::Full => None,
        ReadSelector::Lines { start, end } => Some(format!("{start}-{end}")),
        ReadSelector::Heading(heading) => {
            let file_type = crate::read::detect_file_type(path);
            if !matches!(file_type, crate::types::FileType::Markdown) {
                return Err(PatchError::InvalidQuery {
                    query: heading.clone(),
                    reason: "heading selectors are only supported for markdown files".into(),
                });
            }
            Some(heading.clone())
        }
    };

    let content = crate::read::read_file(path, legacy_section.as_deref(), full, &cache, false)?;
    let content = match budget {
        Some(budget) => crate::budget::apply(&content, budget),
        None => content,
    };

    let selector = match selector {
        ReadSelector::Full => ReadSelectorData::Full,
        ReadSelector::Lines { start, end } => ReadSelectorData::Lines { start, end },
        ReadSelector::Heading(value) => ReadSelectorData::Heading { value },
    };

    Ok(ReadCommandResult {
        data: ReadResultData {
            path: path.display().to_string(),
            selector,
            content,
        },
        diagnostics: vec![Diagnostic {
            level: DiagnosticLevel::Hint,
            code: "no_diagnostics".into(),
            message: "no diagnostics".into(),
            suggestion: None,
        }],
    })
}
