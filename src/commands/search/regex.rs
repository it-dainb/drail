use crate::cli::args::SearchRegexArgs;
use crate::engine::search;
use crate::error::PatchError;
use crate::output::CommandOutput;
use crate::output::{json, text};

pub fn run(args: &SearchRegexArgs) -> Result<CommandOutput, PatchError> {
    let result = search::run_regex(&args.pattern, &args.scope, args.budget)?;

    Ok(CommandOutput::with_parts(
        "search.regex",
        text::search::render(&result),
        json::search::render(&result),
        result.diagnostics,
        true,
    ))
}
