use std::fmt::Write;

use crate::engine::search::{SearchCommandResult, SearchMode};

#[must_use]
pub fn render(result: &SearchCommandResult) -> String {
    let mut output = String::new();
    let mode = match result.data.mode {
        SearchMode::Text => "text",
        SearchMode::Regex => "regex",
    };

    let _ = write!(
        output,
        "search {mode} \"{}\" in {} — {} match{}",
        result.data.query,
        result.data.scope,
        result.data.matches.len(),
        if result.data.matches.len() == 1 {
            ""
        } else {
            "es"
        }
    );

    for entry in &result.data.matches {
        let _ = write!(
            output,
            "\n\n- {}:{}\n  {}",
            entry.path, entry.line, entry.text
        );
    }

    output
}
