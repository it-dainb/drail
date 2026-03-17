use crate::engine::read::ReadCommandResult;

#[must_use]
pub fn render(result: &ReadCommandResult) -> String {
    result.data.content.clone()
}
