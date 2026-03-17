use serde_json::Value;

use crate::engine::search::SearchCommandResult;

#[must_use]
pub fn render(result: &SearchCommandResult) -> Value {
    serde_json::to_value(&result.data).expect("search data should serialize")
}
