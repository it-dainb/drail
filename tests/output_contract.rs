use std::ffi::OsStr;
use std::process::Output;

use assert_cmd::Command;
use serde_json::Value;

fn run_patch<I, S>(args: I) -> Output
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    Command::cargo_bin("patch")
        .expect("patch binary should build for integration tests")
        .args(args)
        .output()
        .expect("patch should execute")
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn assert_success(output: &Output) {
    assert!(
        output.status.success(),
        "expected success, got status {:?}\nstdout:\n{}\nstderr:\n{}",
        output.status.code(),
        stdout(output),
        stderr(output)
    );
}

fn run_patch_json<I, S>(args: I) -> Value
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let output = run_patch(args);
    assert_success(&output);
    serde_json::from_slice(&output.stdout).unwrap_or_else(|error| {
        panic!(
            "expected valid json stdout, got error: {error}\nstdout:\n{}\nstderr:\n{}",
            stdout(&output),
            stderr(&output)
        )
    })
}

fn diagnostics<'a>(value: &'a Value, command: &str) -> &'a [Value] {
    value["diagnostics"].as_array().unwrap_or_else(|| {
        panic!(
            "expected {command} diagnostics to be an array, got:\n{}",
            serde_json::to_string_pretty(value).expect("json value should serialize")
        )
    })
}

fn collect_levels(items: &[Value]) -> Vec<&str> {
    items
        .iter()
        .map(|diagnostic| {
            diagnostic["level"].as_str().unwrap_or_else(|| {
                panic!(
                    "expected diagnostic level to be a string, got:\n{}",
                    serde_json::to_string_pretty(diagnostic).expect("json value should serialize")
                )
            })
        })
        .collect()
}

fn count_level(items: &[Value], level: &str) -> usize {
    collect_levels(items)
        .into_iter()
        .filter(|candidate| *candidate == level)
        .count()
}

fn assert_shared_envelope(value: &Value, command: &str) {
    assert_eq!(value["command"], command);
    assert_eq!(value["schema_version"], 1);
    assert!(value["ok"].is_boolean(), "expected ok boolean: {value:#}");
    assert!(value["data"].is_object(), "expected data object: {value:#}");
    assert!(
        value["diagnostics"].is_array(),
        "expected diagnostics array: {value:#}"
    );
}

fn assert_diagnostic_schema(items: &[Value]) {
    for diagnostic in items {
        let object = diagnostic.as_object().unwrap_or_else(|| {
            panic!(
                "expected diagnostic object, got:\n{}",
                serde_json::to_string_pretty(diagnostic).expect("json value should serialize")
            )
        });

        let level = object
            .get("level")
            .and_then(Value::as_str)
            .unwrap_or_else(|| {
                panic!(
                    "expected diagnostic level string, got:\n{}",
                    serde_json::to_string_pretty(diagnostic).expect("json value should serialize")
                )
            });
        assert!(matches!(level, "error" | "warning" | "hint"));

        assert!(
            object.get("code").and_then(Value::as_str).is_some(),
            "expected diagnostic code string, got:\n{}",
            serde_json::to_string_pretty(diagnostic).expect("json value should serialize")
        );
        assert!(
            object.get("message").and_then(Value::as_str).is_some(),
            "expected diagnostic message string, got:\n{}",
            serde_json::to_string_pretty(diagnostic).expect("json value should serialize")
        );

        if let Some(suggestion) = object.get("suggestion") {
            assert!(
                suggestion.is_string(),
                "expected optional diagnostic suggestion string, got:\n{}",
                serde_json::to_string_pretty(diagnostic).expect("json value should serialize")
            );
        }
    }
}

fn assert_text_section_order(output: &str) {
    let mut lines = output.lines();
    let first_line = lines.next().expect("expected at least one output line");
    assert!(
        first_line.starts_with("# "),
        "expected summary header first, got:\n{output}"
    );

    let evidence_index = output
        .find("## Evidence")
        .unwrap_or_else(|| panic!("expected evidence block in output:\n{output}"));
    let diagnostics_index = output
        .find("## Diagnostics")
        .unwrap_or_else(|| panic!("expected diagnostics block in output:\n{output}"));
    assert!(
        evidence_index < diagnostics_index,
        "expected evidence before diagnostics:\n{output}"
    );

    let diagnostics_block = &output[diagnostics_index..];
    let error_index = diagnostics_block.find("[error]");
    let warning_index = diagnostics_block.find("[warning]");
    let hint_index = diagnostics_block.find("[hint]");

    if let (Some(error_index), Some(warning_index)) = (error_index, warning_index) {
        assert!(
            error_index < warning_index,
            "expected errors before warnings:\n{output}"
        );
    }
    if let (Some(warning_index), Some(hint_index)) = (warning_index, hint_index) {
        assert!(
            warning_index < hint_index,
            "expected warnings before hints:\n{output}"
        );
    }
    if let (Some(error_index), Some(hint_index)) = (error_index, hint_index) {
        assert!(
            error_index < hint_index,
            "expected errors before hints:\n{output}"
        );
    }

    let trimmed = output.trim_end();
    assert!(
        trimmed.ends_with("[hint]")
            || trimmed.ends_with("[warning]")
            || trimmed.ends_with("[error]"),
        "expected diagnostics section to render at the end:\n{output}"
    );
}

#[test]
fn symbol_find_json_uses_shared_envelope() {
    let value = run_patch_json(["symbol", "find", "main", "--scope", "src", "--json"]);

    assert_shared_envelope(&value, "symbol.find");
    assert!(
        value["data"]["matches"].is_array(),
        "expected symbol.find matches array: {value:#}"
    );
}

#[test]
fn symbol_find_json_pins_diagnostic_object_schema() {
    let value = run_patch_json([
        "symbol",
        "find",
        "missing_symbol",
        "--scope",
        "src",
        "--json",
    ]);

    assert_shared_envelope(&value, "symbol.find");
    assert_diagnostic_schema(diagnostics(&value, "symbol.find"));
}

#[test]
fn symbol_find_json_contract_exposes_kind_path_and_range() {
    let value = run_patch_json([
        "symbol",
        "find",
        "main",
        "--scope",
        "src",
        "--kind",
        "definition",
        "--json",
    ]);

    assert_shared_envelope(&value, "symbol.find");
    let matches = value["data"]["matches"].as_array().unwrap_or_else(|| {
        panic!(
            "expected symbol.find matches array, got:\n{}",
            serde_json::to_string_pretty(&value).expect("json value should serialize")
        )
    });
    let first = matches
        .first()
        .unwrap_or_else(|| panic!("expected at least one symbol match: {value:#}"));

    assert!(first["path"].is_string(), "expected path string: {first:#}");
    assert!(first["kind"].is_string(), "expected kind string: {first:#}");
    assert!(
        first["range"]["start"].is_u64(),
        "expected range.start number: {first:#}"
    );
    assert!(
        first["range"]["end"].is_u64(),
        "expected range.end number: {first:#}"
    );
}

#[test]
fn symbol_find_json_no_match_has_exactly_one_suggestion() {
    let value = run_patch_json([
        "symbol",
        "find",
        "definitely_missing_symbol_xyz",
        "--scope",
        "src",
        "--json",
    ]);

    assert_shared_envelope(&value, "symbol.find");
    let diagnostics = diagnostics(&value, "symbol.find");
    let suggestions = diagnostics
        .iter()
        .filter(|diagnostic| diagnostic.get("suggestion").is_some())
        .count();
    assert_eq!(suggestions, 1, "expected exactly one suggestion: {value:#}");
}

#[test]
fn invalid_regex_json_returns_exactly_one_error_diagnostic() {
    let value = run_patch_json(["search", "regex", "(", "--scope", "src", "--json"]);
    let diagnostics = diagnostics(&value, "search.regex");

    assert_shared_envelope(&value, "search.regex");
    assert_diagnostic_schema(diagnostics);
    assert_eq!(count_level(diagnostics, "error"), 1);
}

#[test]
fn diagnostics_json_stays_within_warning_and_hint_limits() {
    let value = run_patch_json(["symbol", "find", "main", "--scope", "src", "--json"]);
    let diagnostics = diagnostics(&value, "symbol.find");

    assert_shared_envelope(&value, "symbol.find");
    assert_diagnostic_schema(diagnostics);
    assert!(
        count_level(diagnostics, "warning") <= 2,
        "expected no more than 2 warnings, got:\n{}",
        serde_json::to_string_pretty(diagnostics).expect("json value should serialize")
    );
    assert!(
        count_level(diagnostics, "hint") <= 1,
        "expected no more than 1 hint, got:\n{}",
        serde_json::to_string_pretty(diagnostics).expect("json value should serialize")
    );
}

#[test]
fn symbol_find_text_orders_evidence_before_diagnostics() {
    let output = run_patch(["symbol", "find", "main", "--scope", "src"]);

    assert_success(&output);
    assert_text_section_order(&stdout(&output));
}

#[test]
fn symbol_callers_json_uses_shared_envelope() {
    let value = run_patch_json([
        "symbol",
        "callers",
        "render",
        "--scope",
        "src/output",
        "--json",
    ]);

    assert_shared_envelope(&value, "symbol.callers");
    assert!(
        value["data"]["callers"].is_array(),
        "expected symbol.callers callers array: {value:#}"
    );
    assert!(
        value["data"]["impact"].is_array(),
        "expected symbol.callers impact array: {value:#}"
    );
}

#[test]
fn symbol_callers_json_pins_diagnostic_object_schema() {
    let value = run_patch_json([
        "symbol",
        "callers",
        "SymbolCommand",
        "--scope",
        "src",
        "--json",
    ]);

    assert_shared_envelope(&value, "symbol.callers");
    assert_diagnostic_schema(diagnostics(&value, "symbol.callers"));
}

#[test]
fn symbol_callers_text_orders_evidence_before_diagnostics() {
    let output = run_patch(["symbol", "callers", "render", "--scope", "src/output"]);

    assert_success(&output);
    assert_text_section_order(&stdout(&output));
}

#[test]
fn read_json_uses_shared_envelope() {
    let value = run_patch_json(["read", "README.md", "--lines", "1:4", "--json"]);

    assert_shared_envelope(&value, "read");
}

#[test]
fn read_json_reports_exactly_one_error_for_invalid_selector() {
    let value = run_patch_json(["read", "README.md", "--lines", "4:1", "--json"]);
    let diagnostics = diagnostics(&value, "read");

    assert_shared_envelope(&value, "read");
    assert_diagnostic_schema(diagnostics);
    assert_eq!(count_level(diagnostics, "error"), 1);
}

#[test]
fn read_text_orders_evidence_before_diagnostics() {
    let output = run_patch(["read", "README.md", "--lines", "1:4"]);

    assert_success(&output);
    assert_text_section_order(&stdout(&output));
}

#[test]
fn search_text_json_uses_shared_envelope() {
    let value = run_patch_json([
        "search",
        "text",
        "symbol callers",
        "--scope",
        "src",
        "--json",
    ]);

    assert_shared_envelope(&value, "search.text");
    assert!(
        value["data"]["matches"].is_array(),
        "expected search.text matches array: {value:#}"
    );
}

#[test]
fn search_regex_json_uses_shared_envelope() {
    let value = run_patch_json([
        "search",
        "regex",
        "symbol\\s+callers",
        "--scope",
        "src",
        "--json",
    ]);

    assert_shared_envelope(&value, "search.regex");
    assert!(
        value["data"]["matches"].is_array(),
        "expected search.regex matches array: {value:#}"
    );
}

#[test]
fn search_regex_json_pins_diagnostic_object_schema() {
    let value = run_patch_json(["search", "regex", "(", "--scope", "src", "--json"]);

    assert_shared_envelope(&value, "search.regex");
    assert_diagnostic_schema(diagnostics(&value, "search.regex"));
}

#[test]
fn search_text_text_orders_evidence_before_diagnostics() {
    let output = run_patch(["search", "text", "symbol callers", "--scope", "src"]);

    assert_success(&output);
    assert_text_section_order(&stdout(&output));
}

#[test]
fn search_regex_text_orders_evidence_before_diagnostics() {
    let output = run_patch(["search", "regex", "symbol\\s+callers", "--scope", "src"]);

    assert_success(&output);
    assert_text_section_order(&stdout(&output));
}

#[test]
fn files_json_uses_shared_envelope() {
    let value = run_patch_json(["files", "*.rs", "--scope", "src/output", "--json"]);

    assert_shared_envelope(&value, "files");
    assert!(
        value["data"]["files"].is_array(),
        "expected files array: {value:#}"
    );
}

#[test]
fn files_json_pins_diagnostic_object_schema() {
    let value = run_patch_json([
        "files",
        "*.definitelymissingxyz",
        "--scope",
        "src",
        "--json",
    ]);

    assert_shared_envelope(&value, "files");
    assert_diagnostic_schema(diagnostics(&value, "files"));
}

#[test]
fn files_text_orders_evidence_before_diagnostics() {
    let output = run_patch(["files", "*.rs", "--scope", "src/output"]);

    assert_success(&output);
    assert_text_section_order(&stdout(&output));
}

#[test]
fn deps_json_uses_shared_envelope() {
    let value = run_patch_json(["deps", "src/commands/deps.rs", "--scope", "src", "--json"]);

    assert_shared_envelope(&value, "deps");
    assert!(
        value["data"]["uses_local"].is_array(),
        "expected deps local dependency array: {value:#}"
    );
    assert!(
        value["data"]["uses_external"].is_array(),
        "expected deps external dependency array: {value:#}"
    );
    assert!(
        value["data"]["used_by"].is_array(),
        "expected deps reverse dependency array: {value:#}"
    );
}

#[test]
fn deps_json_pins_diagnostic_object_schema() {
    let value = run_patch_json(["deps", "render", "--scope", "src", "--json"]);

    assert_shared_envelope(&value, "deps");
    assert_diagnostic_schema(diagnostics(&value, "deps"));
}

#[test]
fn deps_text_orders_evidence_before_diagnostics() {
    let output = run_patch(["deps", "src/commands/deps.rs", "--scope", "src"]);

    assert_success(&output);
    assert_text_section_order(&stdout(&output));
}

#[test]
fn map_json_uses_shared_envelope() {
    let value = run_patch_json(["map", "--scope", "src", "--json"]);

    assert_shared_envelope(&value, "map");
    assert!(
        value["data"]["entries"].is_array(),
        "expected map entries array: {value:#}"
    );
    assert!(
        value["data"]["total_files"].is_number(),
        "expected map total_files number: {value:#}"
    );
}

#[test]
fn map_json_pins_diagnostic_object_schema() {
    let value = run_patch_json(["map", "--scope", "src", "--json"]);

    assert_shared_envelope(&value, "map");
    assert_diagnostic_schema(diagnostics(&value, "map"));
}

#[test]
fn map_text_orders_evidence_before_diagnostics() {
    let output = run_patch(["map", "--scope", "src"]);

    assert_success(&output);
    assert_text_section_order(&stdout(&output));
}
