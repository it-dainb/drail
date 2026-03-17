use crate::cli::args::FilesArgs;
use crate::engine::files;
use crate::error::PatchError;
use crate::output::CommandOutput;
use crate::output::{json, text};

pub fn run(args: &FilesArgs) -> Result<CommandOutput, PatchError> {
    let result = files::run(&args.pattern, &args.scope, args.budget)?;

    Ok(CommandOutput::with_parts(
        "files",
        text::files::render(&result),
        json::files::render(&result),
        result.diagnostics,
        true,
    ))
}
