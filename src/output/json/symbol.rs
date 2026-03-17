use serde_json::Value;

use crate::engine::symbol::{SymbolCallersCommandResult, SymbolFindCommandResult};

#[must_use]
pub fn render(result: &SymbolFindCommandResult) -> Value {
    serde_json::to_value(&result.data).expect("symbol data should serialize")
}

#[must_use]
pub fn render_callers(result: &SymbolCallersCommandResult) -> Value {
    serde_json::to_value(&result.data).expect("symbol callers data should serialize")
}
