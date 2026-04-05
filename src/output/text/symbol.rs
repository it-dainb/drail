use std::fmt::Write;

use crate::engine::symbol::{SymbolCallersCommandResult, SymbolFindCommandResult, SymbolMatchKind};

#[must_use]
pub fn render(result: &SymbolFindCommandResult) -> String {
    let mut output = String::new();
    let kind_suffix = result.data.kind.map_or("", |kind| match kind {
        SymbolMatchKind::Definition => " [definition]",
        SymbolMatchKind::Usage => " [usage]",
    });

    let _ = write!(
        output,
        "symbol find \"{}\"{} in {} — {} match{}",
        result.data.query,
        kind_suffix,
        result.data.scope,
        result.data.matches.len(),
        if result.data.matches.len() == 1 {
            ""
        } else {
            "es"
        }
    );

    if result.data.hierarchy.len() > 1 {
        let _ = write!(
            output,
            "\n\nHierarchy: {}",
            result.data.hierarchy.join(" -> ")
        );
    }

    for entry in &result.data.matches {
        let _ = write!(
            output,
            "\n\n- {}:{}-{} [{}]",
            entry.path,
            entry.range.start,
            entry.range.end,
            match entry.kind {
                SymbolMatchKind::Definition => "definition",
                SymbolMatchKind::Usage => "usage",
            }
        );
        if let Some(snippet) = &entry.snippet {
            let _ = write!(output, "\n  {snippet}");
        }
        if !entry.parents.is_empty() {
            let _ = write!(output, "\n  Parents: {}", entry.parents.join(", "));
        }
    }

    output
}

#[must_use]
pub fn render_callers(result: &SymbolCallersCommandResult) -> String {
    let mut output = String::new();
    let _ = write!(
        output,
        "symbol callers \"{}\" in {} — {} call site{}",
        result.data.query,
        result.data.scope,
        result.data.callers.len(),
        if result.data.callers.len() == 1 {
            ""
        } else {
            "s"
        }
    );

    for caller in &result.data.callers {
        let _ = write!(
            output,
            "\n\n- {}:{} [{}]\n  {}",
            caller.path, caller.line, caller.caller, caller.call_text
        );
    }

    if !result.data.impact.is_empty() {
        output.push_str("\n\nImpact (2nd hop):");
        for entry in &result.data.impact {
            let _ = write!(
                output,
                "\n- {}:{} [{}] via {}",
                entry.path, entry.line, entry.caller, entry.via
            );
        }
    }

    output
}
