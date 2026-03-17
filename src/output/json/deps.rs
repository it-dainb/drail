use serde_json::Value;

use crate::engine::deps::DepsCommandResult;

#[must_use]
pub fn render(result: &DepsCommandResult) -> Value {
    serde_json::to_value(&result.data).expect("deps data should serialize")
}
