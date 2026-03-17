use crate::cli::args::SymbolCallersArgs;
use crate::engine::symbol;
use crate::error::PatchError;
use crate::output::CommandOutput;
use crate::output::{json, text};

pub fn run(args: &SymbolCallersArgs) -> Result<CommandOutput, PatchError> {
    let result = symbol::run_callers(&args.query, &args.scope, args.budget)?;

    Ok(CommandOutput::with_parts(
        "symbol.callers",
        text::symbol::render_callers(&result),
        json::symbol::render_callers(&result),
        result.diagnostics,
        true,
    ))
}
