use std::fmt::Write;

use crate::engine::scan::ScanCommandResult;

#[must_use]
pub fn render(result: &ScanCommandResult) -> String {
    let mut output = String::new();

    let total_scopes = result.data.scopes.len();
    let total_patterns: usize = result.data.scopes.first().map_or(0, |s| s.pattern_count);
    let total_files: usize = result.data.scopes.iter().map(|s| s.total_files).sum();

    let _ = write!(
        output,
        "--- scan: {} scope{}, {} pattern{}, {} file{} matched ---",
        total_scopes,
        if total_scopes == 1 { "" } else { "s" },
        total_patterns,
        if total_patterns == 1 { "" } else { "s" },
        total_files,
        if total_files == 1 { "" } else { "s" },
    );

    for scope_data in &result.data.scopes {
        let _ = write!(output, "\n\n[scope: {}]", scope_data.scope);

        // Files
        if scope_data.files.is_empty() {
            let _ = write!(output, "\nfiles ({}): (none)", scope_data.total_files);
        } else {
            let _ = write!(output, "\nfiles ({}):", scope_data.total_files);
            for entry in &scope_data.files {
                let _ = write!(output, "\n  {} — {}", entry.path, entry.preview);
            }
        }

        // Matches
        if scope_data.matches.is_empty() {
            if scope_data.total_matches > 0 {
                let _ = write!(
                    output,
                    "\nmatches ({}): (trimmed)",
                    scope_data.total_matches
                );
            }
        } else {
            let _ = write!(output, "\nmatches ({}):", scope_data.total_matches);
            for entry in &scope_data.matches {
                let _ = write!(output, "\n  {}:{}: {}", entry.path, entry.line, entry.text);
            }
        }

        // Summaries
        if scope_data.summaries.is_empty() {
            if scope_data.total_summaries > 0 {
                let _ = write!(
                    output,
                    "\nread-summaries ({}): (trimmed)",
                    scope_data.total_summaries
                );
            }
        } else {
            let _ = write!(output, "\nread-summaries ({}):", scope_data.total_summaries);
            for entry in &scope_data.summaries {
                let _ = write!(
                    output,
                    "\n  {} ({} lines):\n    {}",
                    entry.path,
                    entry.lines,
                    entry.outline.replace('\n', "\n    ")
                );
            }
        }
    }

    output
}
