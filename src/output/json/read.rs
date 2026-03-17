use serde_json::Value;

use crate::engine::read::ReadCommandResult;

#[must_use]
pub fn render(result: &ReadCommandResult) -> Value {
    serde_json::to_value(&result.data).expect("read data should serialize")
}
