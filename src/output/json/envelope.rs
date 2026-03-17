use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct Diagnostic {
    pub level: DiagnosticLevel,
    pub code: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub suggestion: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DiagnosticLevel {
    Error,
    Warning,
    Hint,
}

#[derive(Debug, Clone, Serialize)]
pub struct Envelope<T> {
    pub command: String,
    pub schema_version: u32,
    pub ok: bool,
    pub data: T,
    pub diagnostics: Vec<Diagnostic>,
}
