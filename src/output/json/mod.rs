pub mod deps;
pub mod envelope;
pub mod files;
pub mod map;
pub mod read;
pub mod search;
pub mod symbol;

use crate::output::CommandOutput;

#[must_use]
pub fn render(output: &CommandOutput) -> String {
    serde_json::to_string_pretty(&crate::output::envelope(output))
        .expect("json output should serialize")
}
