use crate::engine::map::MapCommandResult;

#[must_use]
pub fn render(result: &MapCommandResult) -> String {
    result.data.tree_text.clone()
}
