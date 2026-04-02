use std::collections::HashSet;
use std::path::{Path, PathBuf};

use serde::Serialize;

use crate::error::DrailError;
use crate::output::json::envelope::{Diagnostic, DiagnosticLevel};

#[derive(Debug, Clone, Serialize)]
pub struct ScanFileEntry {
    pub path: String,
    pub preview: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ScanSearchMatch {
    pub path: String,
    pub line: usize,
    pub text: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ScanReadSummary {
    pub path: String,
    pub lines: usize,
    pub outline: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ScanScopeData {
    pub scope: String,
    pub pattern_count: usize,
    pub total_files: usize,
    pub total_matches: usize,
    pub total_summaries: usize,
    pub files: Vec<ScanFileEntry>,
    pub matches: Vec<ScanSearchMatch>,
    pub summaries: Vec<ScanReadSummary>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ScanData {
    pub scopes: Vec<ScanScopeData>,
}

#[derive(Debug, Clone)]
pub struct ScanCommandResult {
    pub data: ScanData,
    pub diagnostics: Vec<Diagnostic>,
}

pub fn run(
    scopes: &[PathBuf],
    patterns: &[String],
    file_globs: &[String],
    read_matching: bool,
    budget: Option<u64>,
) -> Result<ScanCommandResult, DrailError> {
    let mut scope_results = Vec::new();
    let mut all_diagnostics = Vec::new();

    for scope_path in scopes {
        let scope = crate::engine::resolve_scope(scope_path);

        if !scope.exists() {
            all_diagnostics.push(Diagnostic {
                level: DiagnosticLevel::Error,
                code: "scope_not_found".into(),
                message: format!("scope not found: {}", scope.display()),
                suggestion: None,
            });
            continue;
        }

        match run_scope(&scope, patterns, file_globs, read_matching) {
            Ok(result) => {
                if result.files.is_empty() && result.matches.is_empty() {
                    all_diagnostics.push(Diagnostic {
                        level: DiagnosticLevel::Hint,
                        code: "no_scan_matches".into(),
                        message: format!(
                            "no files or matches found in scope {}",
                            scope.display()
                        ),
                        suggestion: None,
                    });
                }
                scope_results.push(result);
            }
            Err(e) => {
                all_diagnostics.push(Diagnostic {
                    level: DiagnosticLevel::Error,
                    code: "scan_scope_error".into(),
                    message: format!("error scanning {}: {e}", scope.display()),
                    suggestion: None,
                });
            }
        }
    }

    // Sort scopes by path for deterministic output
    scope_results.sort_by(|a, b| a.scope.cmp(&b.scope));

    let mut result = ScanCommandResult {
        data: ScanData {
            scopes: scope_results,
        },
        diagnostics: all_diagnostics,
    };

    if let Some(budget) = budget {
        apply_budget(&mut result.data, budget);
    }

    Ok(result)
}

fn run_scope(
    scope: &Path,
    patterns: &[String],
    file_globs: &[String],
    read_matching: bool,
) -> Result<ScanScopeData, DrailError> {
    // 1. File discovery: union multiple globs, default to "*" for all files
    let globs = if file_globs.is_empty() {
        vec!["*".to_string()]
    } else {
        file_globs.to_vec()
    };

    let mut seen_paths: HashSet<PathBuf> = HashSet::new();
    let mut files: Vec<ScanFileEntry> = Vec::new();

    for glob in &globs {
        let glob_result = crate::search::glob::search(glob, scope)?;
        for entry in glob_result.files {
            if seen_paths.insert(entry.path.clone()) {
                let rel_path = entry
                    .path
                    .strip_prefix(scope)
                    .unwrap_or(&entry.path)
                    .display()
                    .to_string();
                files.push(ScanFileEntry {
                    path: rel_path,
                    preview: entry.preview.unwrap_or_else(|| "(no preview)".into()),
                });
            }
        }
    }

    let total_files = files.len();

    // 2. Search: combine patterns with non-capturing groups, post-filter to glob-matched set
    let mut matches: Vec<ScanSearchMatch> = Vec::new();
    let mut total_matches = 0;

    if !patterns.is_empty() {
        let combined = patterns
            .iter()
            .map(|p| format!("(?:{p})"))
            .collect::<Vec<_>>()
            .join("|");

        let search_result =
            crate::search::content::search(&combined, scope, true, None)?;

        // Post-filter: only keep matches in the glob-matched file set
        let matched_paths: HashSet<&str> = files.iter().map(|f| f.path.as_str()).collect();

        for m in search_result.matches {
            let rel_path = m
                .path
                .strip_prefix(scope)
                .unwrap_or(&m.path)
                .display()
                .to_string();
            if matched_paths.contains(rel_path.as_str()) {
                matches.push(ScanSearchMatch {
                    path: rel_path,
                    line: m.line as usize,
                    text: m.text,
                });
            }
        }
        total_matches = matches.len();
    }

    // 3. Outline generation: always outline, never full content
    let mut summaries: Vec<ScanReadSummary> = Vec::new();
    let mut total_summaries = 0;

    if read_matching && !matches.is_empty() {
        let unique_paths: HashSet<&str> = matches.iter().map(|m| m.path.as_str()).collect();
        let mut sorted_paths: Vec<&str> = unique_paths.into_iter().collect();
        sorted_paths.sort_unstable();

        for rel_path in sorted_paths {
            let full_path = scope.join(rel_path);
            if let Ok(buf) = std::fs::read(&full_path) {
                let content = String::from_utf8_lossy(&buf);
                let line_count = content.lines().count();
                let file_type = crate::read::detect_file_type(&full_path);
                let outline =
                    crate::read::outline::generate(&full_path, file_type, &content, &buf, true);

                summaries.push(ScanReadSummary {
                    path: rel_path.to_string(),
                    lines: line_count,
                    outline,
                });
            }
        }
        total_summaries = summaries.len();
    }

    Ok(ScanScopeData {
        scope: scope.display().to_string(),
        pattern_count: patterns.len(),
        total_files,
        total_matches,
        total_summaries,
        files,
        matches,
        summaries,
    })
}

fn apply_budget(data: &mut ScanData, budget: u64) {
    // Tiered trimming: summaries first (longest outline first), then matches, then files
    loop {
        let serialized = serde_json::to_string(data).expect("scan data should serialize");
        if serialized.len() as u64 <= budget {
            break;
        }

        // Tier 1: Remove the longest summary across all scopes
        let longest = data
            .scopes
            .iter()
            .enumerate()
            .flat_map(|(i, s)| {
                s.summaries
                    .iter()
                    .enumerate()
                    .map(move |(j, sum)| (i, j, sum.outline.len()))
            })
            .max_by_key(|&(_, _, len)| len);

        if let Some((scope_idx, summary_idx, _)) = longest {
            data.scopes[scope_idx].summaries.remove(summary_idx);
            continue;
        }

        // Tier 2: Remove matches from scope with the most matches
        let most_matches = data
            .scopes
            .iter()
            .enumerate()
            .filter(|(_, s)| !s.matches.is_empty())
            .max_by_key(|(_, s)| s.matches.len());

        if let Some((scope_idx, _)) = most_matches {
            data.scopes[scope_idx].matches.pop();
            continue;
        }

        // Tier 3: Remove files from scope with the most files
        let most_files = data
            .scopes
            .iter()
            .enumerate()
            .filter(|(_, s)| !s.files.is_empty())
            .max_by_key(|(_, s)| s.files.len());

        if let Some((scope_idx, _)) = most_files {
            data.scopes[scope_idx].files.pop();
            continue;
        }

        // Nothing left to trim
        break;
    }
}
