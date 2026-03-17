use std::fmt::Write;

use crate::engine::deps::DepsCommandResult;

#[must_use]
pub fn render(result: &DepsCommandResult) -> String {
    let mut output = String::new();
    let dependent_count = result.data.used_by.len() + result.data.truncated_dependents;

    let _ = write!(
        output,
        "deps \"{}\" in {} — {} local, {} external, {} dependent{}",
        result.data.path,
        result.data.scope,
        result.data.uses_local.len(),
        result.data.uses_external.len(),
        dependent_count,
        if dependent_count == 1 { "" } else { "s" }
    );

    output.push_str("\n\nUses (local)");
    if result.data.uses_local.is_empty() {
        output.push_str("\n- (none)");
    } else {
        for dependency in &result.data.uses_local {
            let _ = write!(output, "\n- {}", dependency.path);
            if !dependency.symbols.is_empty() {
                let _ = write!(output, "\n  symbols: {}", dependency.symbols.join(", "));
            }
        }
    }

    output.push_str("\n\nUses (external)");
    if result.data.uses_external.is_empty() {
        output.push_str("\n- (none)");
    } else {
        for dependency in &result.data.uses_external {
            let _ = write!(output, "\n- {dependency}");
        }
    }

    output.push_str("\n\nUsed by");
    if result.data.used_by.is_empty() {
        output.push_str("\n- (none)");
    } else {
        for dependency in &result.data.used_by {
            let _ = write!(output, "\n- {}", dependency.path);
            if dependency.is_test {
                output.push_str(" [test]");
            }

            for caller in &dependency.callers {
                let _ = write!(
                    output,
                    "\n  - {}:{} -> {}",
                    dependency.path, caller.line, caller.caller
                );
                if !caller.symbols.is_empty() {
                    let _ = write!(output, " ({})", caller.symbols.join(", "));
                }
            }
        }
    }

    if result.data.truncated_dependents > 0 {
        let _ = write!(
            output,
            "\n\n... and {} more dependent{}",
            result.data.truncated_dependents,
            if result.data.truncated_dependents == 1 {
                ""
            } else {
                "s"
            }
        );
    }

    output
}
