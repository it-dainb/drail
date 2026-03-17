use crate::cli::args::SymbolFindArgs;
use crate::engine::symbol;
use crate::error::PatchError;
use crate::output::CommandOutput;
use crate::output::{json, text};

pub fn run(args: &SymbolFindArgs) -> Result<CommandOutput, PatchError> {
    let result = symbol::run(&args.query, &args.scope, args.kind, args.budget)?;

    Ok(CommandOutput::with_parts(
        "symbol.find",
        text::symbol::render(&result),
        json::symbol::render(&result),
        result.diagnostics,
        true,
    ))
}
