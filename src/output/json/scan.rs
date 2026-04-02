use crate::engine::scan::ScanCommandResult;

#[must_use]
pub fn render(result: &ScanCommandResult) -> serde_json::Value {
    serde_json::to_value(&result.data).expect("scan data should serialize")
}
