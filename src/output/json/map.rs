use serde_json::Value;

use crate::engine::map::MapCommandResult;

#[must_use]
pub fn render(result: &MapCommandResult) -> Value {
    serde_json::to_value(&result.data).expect("map data should serialize")
}
