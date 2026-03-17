use crate::cli::args::SearchTextArgs;
use crate::engine::search;
use crate::error::PatchError;
use crate::output::CommandOutput;
use crate::output::{json, text};

pub fn run(args: &SearchTextArgs) -> Result<CommandOutput, PatchError> {
    let result = search::run_text(&args.query, &args.scope, args.budget)?;

    Ok(CommandOutput::with_parts(
        "search.text",
        text::search::render(&result),
        json::search::render(&result),
        result.diagnostics,
        true,
    ))
}
