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

fn diagnostics(value: &Value) -> &[Value] {
    value["diagnostics"].as_array().unwrap_or_else(|| {
        panic!(
            "expected diagnostics array, got:\n{}",
            serde_json::to_string_pretty(value).expect("json value should serialize")
        )
    })
}

#[test]
fn search_text_returns_typed_matches() {
    let value = run_patch_json([
        "search",
        "text",
        "symbol callers",
        "--scope",
        "src",
        "--json",
    ]);

    assert_eq!(value["command"], "search.text");
    assert_eq!(value["ok"], true);

    let matches = value["data"]["matches"].as_array().unwrap_or_else(|| {
        panic!(
            "expected search.text matches array, got:\n{}",
            serde_json::to_string_pretty(&value).expect("json value should serialize")
        )
    });

    assert!(
        !matches.is_empty(),
        "expected at least one text search match: {value:#}"
    );
    let first = &matches[0];
    assert!(first["path"].is_string(), "expected path string: {first:#}");
    assert!(first["line"].is_u64(), "expected line number: {first:#}");
    assert!(first["text"].is_string(), "expected text string: {first:#}");
}

#[test]
fn search_regex_returns_typed_matches() {
    let value = run_patch_json([
        "search",
        "regex",
        "symbol\\s+callers",
        "--scope",
        "src",
        "--json",
    ]);

    assert_eq!(value["command"], "search.regex");
    assert_eq!(value["ok"], true);

    let matches = value["data"]["matches"].as_array().unwrap_or_else(|| {
        panic!(
            "expected search.regex matches array, got:\n{}",
            serde_json::to_string_pretty(&value).expect("json value should serialize")
        )
    });

    assert!(
        !matches.is_empty(),
        "expected at least one regex search match: {value:#}"
    );
}

#[test]
fn search_regex_invalid_pattern_returns_single_error_diagnostic() {
    let value = run_patch_json(["search", "regex", "(", "--scope", "src", "--json"]);
    let diagnostics = diagnostics(&value);

    assert_eq!(value["command"], "search.regex");
    assert_eq!(value["ok"], false);
    assert_eq!(diagnostics.len(), 1, "expected one diagnostic: {value:#}");
    assert_eq!(diagnostics[0]["level"], "error");
}

#[test]
fn search_text_treats_regex_like_input_as_literal_and_hints_about_regex_command() {
    let value = run_patch_json([
        "search",
        "text",
        "/symbol\\s+callers/",
        "--scope",
        "src",
        "--json",
    ]);
    let matches = value["data"]["matches"].as_array().unwrap_or_else(|| {
        panic!(
            "expected search.text matches array, got:\n{}",
            serde_json::to_string_pretty(&value).expect("json value should serialize")
        )
    });
    let diagnostics = diagnostics(&value);

    assert_eq!(value["command"], "search.text");
    assert!(
        matches.is_empty(),
        "expected regex-like literal to stay literal: {value:#}"
    );
    assert!(
        diagnostics.iter().any(|diagnostic| {
            diagnostic["level"] == "hint"
                && diagnostic["suggestion"]
                    .as_str()
                    .is_some_and(|suggestion| suggestion.contains("search regex"))
        }),
        "expected regex guidance hint: {value:#}"
    );
}
