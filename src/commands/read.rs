use crate::cli::args::ReadArgs;
use crate::engine::read::{self, ReadSelector};
use crate::error::PatchError;
use crate::output::CommandOutput;
use crate::output::{json, text};

pub fn run(args: &ReadArgs) -> Result<CommandOutput, PatchError> {
    let selector = parse_selector(args)?;
    let result = read::run(&args.path, selector, args.full, args.budget)?;

    Ok(CommandOutput::with_parts(
        "read",
        text::read::render(&result),
        json::read::render(&result),
        result.diagnostics,
        true,
    ))
}

fn parse_selector(args: &ReadArgs) -> Result<ReadSelector, PatchError> {
    match (&args.lines, &args.heading) {
        (Some(lines), None) => {
            let (start, end) = parse_lines(lines)?;
            Ok(ReadSelector::Lines { start, end })
        }
        (None, Some(heading)) => Ok(ReadSelector::Heading(heading.clone())),
        (None, None) => Ok(ReadSelector::Full),
        (Some(_), Some(_)) => Err(PatchError::InvalidQuery {
            query: "read".into(),
            reason: "--lines cannot be used with --heading".into(),
        }),
    }
}

fn parse_lines(lines: &str) -> Result<(usize, usize), PatchError> {
    let (start, end) = lines
        .split_once(':')
        .ok_or_else(|| PatchError::InvalidQuery {
            query: lines.into(),
            reason: "expected line range in START:END format".into(),
        })?;

    let start = start
        .trim()
        .parse::<usize>()
        .map_err(|_| PatchError::InvalidQuery {
            query: lines.into(),
            reason: "expected line range in START:END format".into(),
        })?;
    let end = end
        .trim()
        .parse::<usize>()
        .map_err(|_| PatchError::InvalidQuery {
            query: lines.into(),
            reason: "expected line range in START:END format".into(),
        })?;

    if start == 0 || end < start {
        return Err(PatchError::InvalidQuery {
            query: lines.into(),
            reason: "line range must start at 1 and end at or after the start line".into(),
        });
    }

    Ok((start, end))
}
