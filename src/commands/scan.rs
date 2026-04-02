use serde_json::{json, Map, Value};

use crate::cli::args::ScanArgs;
use crate::engine::scan;
use crate::error::DrailError;
use crate::output::json::envelope::NextItem;
use crate::output::CommandOutput;
use crate::output::{json, text};

pub fn run(args: &ScanArgs) -> Result<CommandOutput, DrailError> {
    let result = scan::run(
        &args.scope,
        &args.pattern,
        &args.files,
        args.read_matching,
        args.budget,
    )?;

    let mut output = CommandOutput::with_parts(
        "scan",
        text::scan::render(&result),
        json::scan::render(&result),
        result.diagnostics.clone(),
        true,
    );
    output.meta = meta_for_scan(&result);
    output.next = next_for_scan(&result);

    Ok(output)
}

fn meta_for_scan(result: &scan::ScanCommandResult) -> Map<String, Value> {
    let total_files: usize = result.data.scopes.iter().map(|s| s.total_files).sum();
    let total_matches: usize = result.data.scopes.iter().map(|s| s.total_matches).sum();
    let total_summaries: usize = result.data.scopes.iter().map(|s| s.total_summaries).sum();

    let mut meta = Map::new();
    meta.insert("scopes".into(), json!(result.data.scopes.len()));
    meta.insert("total_files".into(), json!(total_files));
    meta.insert("total_matches".into(), json!(total_matches));
    meta.insert("total_summaries".into(), json!(total_summaries));
    meta.insert("stability".into(), json!("high"));
    meta.insert("noise".into(), json!("low"));
    meta
}

fn next_for_scan(result: &scan::ScanCommandResult) -> Vec<NextItem> {
    let has_summaries = result
        .data
        .scopes
        .iter()
        .any(|s| s.total_summaries > 0);

    if has_summaries {
        vec![crate::output::suggestion(
            "Read full content of a specific file",
            "drail read <path> --full",
        )]
    } else if result.data.scopes.iter().any(|s| !s.matches.is_empty()) {
        vec![crate::output::suggestion(
            "Read a matched file for full content",
            "drail read <path> --full",
        )]
    } else {
        Vec::new()
    }
}
