use std::fmt::Write;

use crate::engine::files::FilesCommandResult;

#[must_use]
pub fn render(result: &FilesCommandResult) -> String {
    let mut output = String::new();
    let _ = write!(
        output,
        "files \"{}\" in {} — {} file{}",
        result.data.pattern,
        result.data.scope,
        result.data.files.len(),
        if result.data.files.len() == 1 {
            ""
        } else {
            "s"
        }
    );

    for entry in &result.data.files {
        let _ = write!(output, "\n\n- {}\n  {}", entry.path, entry.preview);
    }

    output
}
