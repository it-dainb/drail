use crate::cli::args::DepsArgs;
use crate::engine::deps;
use crate::error::PatchError;
use crate::output::CommandOutput;
use crate::output::{json, text};

pub fn run(args: &DepsArgs) -> Result<CommandOutput, PatchError> {
    let result = deps::run(&args.path, &args.scope)?;
    let mut output = CommandOutput::with_parts(
        "deps",
        text::deps::render(&result),
        json::deps::render(&result),
        result.diagnostics,
        true,
    );

    if let Some(budget) = args.budget {
        output.text = crate::budget::apply(&output.text, budget);
    }

    Ok(output)
}
