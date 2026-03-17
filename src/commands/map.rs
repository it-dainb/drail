use crate::cli::args::MapArgs;
use crate::engine::map;
use crate::error::PatchError;
use crate::output::CommandOutput;
use crate::output::{json, text};

pub fn run(args: &MapArgs) -> Result<CommandOutput, PatchError> {
    let result = map::run(&args.scope, args.depth, args.budget)?;

    Ok(CommandOutput::with_parts(
        "map",
        text::map::render(&result),
        json::map::render(&result),
        result.diagnostics,
        true,
    ))
}
