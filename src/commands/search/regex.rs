use crate::cli::args::SearchRegexArgs;
use crate::engine::search;
use crate::error::DrailError;
use crate::output::CommandOutput;
use crate::output::{json, text};
use serde_json::{json, Map, Value};

pub fn run(args: &SearchRegexArgs) -> Result<CommandOutput, DrailError> {
    let result = search::run_regex(&args.pattern, &args.scope, args.limit, args.budget)?;
    let mut next: Vec<crate::output::json::envelope::NextItem> = Vec::new();
    if let Some(hint) = crate::output::truncation_hint(
        result.data.matches.len(),
        result.total_found,
        "matches",
        "drail search regex",
        &result.data.query,
        &result.data.scope,
    ) {
        next.push(hint);
    }
    let mut output = CommandOutput::with_parts(
        "search.regex",
        text::search::render(&result),
        json::search::render(&result),
        result.diagnostics,
        true,
    );
    output.meta = meta_for_search(&result.data);
    output.next = next;

    Ok(output)
}

fn meta_for_search(data: &search::SearchData) -> Map<String, Value> {
    let mut meta = Map::new();
    meta.insert("query".into(), json!(data.query));
    meta.insert("scope".into(), json!(data.scope));
    meta.insert("matches".into(), json!(data.matches.len()));
    meta.insert("mode".into(), json!(data.mode));
    meta.insert("stability".into(), json!("high"));
    meta.insert("noise".into(), json!("medium"));
    meta
}
