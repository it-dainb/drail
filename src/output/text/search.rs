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

    if result.data.matches.is_empty() {
        if let Some(suggestion) = result
            .diagnostics
            .iter()
            .find_map(|diagnostic| diagnostic.suggestion.as_deref())
        {
            let _ = write!(output, "\n\nTry: {suggestion}");
        }
    }

    output
}
