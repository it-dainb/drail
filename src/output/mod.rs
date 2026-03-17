pub mod json;
pub mod text;

use serde_json::Value;

use crate::error::PatchError;
use crate::output::json::envelope::{Diagnostic, DiagnosticLevel, Envelope};

pub struct CommandOutput {
    pub command: &'static str,
    pub text: String,
    pub data: Value,
    pub diagnostics: Vec<Diagnostic>,
    pub ok: bool,
}

impl CommandOutput {
    #[must_use]
    pub fn with_parts(
        command: &'static str,
        text: String,
        data: Value,
        diagnostics: Vec<Diagnostic>,
        ok: bool,
    ) -> Self {
        let diagnostics = if diagnostics.is_empty() {
            vec![default_hint()]
        } else {
            diagnostics
        };

        Self {
            command,
            text,
            data,
            diagnostics,
            ok,
        }
    }

    #[must_use]
    pub fn from_error(command: &'static str, error: &PatchError) -> Self {
        Self {
            command,
            text: text::render(command, "", &[diagnostic_from_error(error)]),
            data: serde_json::json!({}),
            diagnostics: vec![diagnostic_from_error(error)],
            ok: false,
        }
    }
}

pub fn write(output: &CommandOutput, json_mode: bool, is_tty: bool) {
    if json_mode {
        println!("{}", json::render(output));
    } else {
        text::write(output, is_tty);
    }
}

fn default_hint() -> Diagnostic {
    Diagnostic {
        level: DiagnosticLevel::Hint,
        code: "no_diagnostics".into(),
        message: "no diagnostics".into(),
        suggestion: None,
    }
}

fn diagnostic_from_error(error: &PatchError) -> Diagnostic {
    match error {
        PatchError::NotFound { suggestion, .. } => Diagnostic {
            level: DiagnosticLevel::Error,
            code: "not_found".into(),
            message: error.to_string(),
            suggestion: suggestion.clone(),
        },
        PatchError::PermissionDenied { .. } => Diagnostic {
            level: DiagnosticLevel::Error,
            code: "permission_denied".into(),
            message: error.to_string(),
            suggestion: None,
        },
        PatchError::InvalidQuery { .. } => Diagnostic {
            level: DiagnosticLevel::Error,
            code: "invalid_query".into(),
            message: error.to_string(),
            suggestion: None,
        },
        PatchError::IoError { .. } => Diagnostic {
            level: DiagnosticLevel::Error,
            code: "io_error".into(),
            message: error.to_string(),
            suggestion: None,
        },
        PatchError::ParseError { .. } => Diagnostic {
            level: DiagnosticLevel::Error,
            code: "parse_error".into(),
            message: error.to_string(),
            suggestion: None,
        },
        PatchError::Clap { .. } => Diagnostic {
            level: DiagnosticLevel::Error,
            code: "clap".into(),
            message: error.to_string(),
            suggestion: None,
        },
    }
}

#[must_use]
pub fn envelope(output: &CommandOutput) -> Envelope<Value> {
    Envelope {
        command: output.command.to_string(),
        schema_version: 1,
        ok: output.ok,
        data: output.data.clone(),
        diagnostics: output.diagnostics.clone(),
    }
}
