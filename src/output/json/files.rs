use serde_json::Value;

use crate::engine::files::FilesCommandResult;

#[must_use]
pub fn render(result: &FilesCommandResult) -> Value {
    serde_json::to_value(&result.data).expect("files data should serialize")
}
