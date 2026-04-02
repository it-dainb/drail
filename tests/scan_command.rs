use std::ffi::OsStr;
use std::process::Output;

use assert_cmd::Command;
use serde_json::Value;

fn run_drail<I, S>(args: I) -> Output
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    Command::cargo_bin("drail")
        .expect("drail binary should build for integration tests")
        .args(args)
        .output()
        .expect("drail should execute")
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn run_drail_json<I, S>(args: I) -> Value
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let output = run_drail(args);
    assert!(
        output.status.success(),
        "expected success, got:\n{}",
        stdout(&output)
    );
    serde_json::from_str(&stdout(&output)).expect("should be valid json")
}

fn assert_success(output: &Output) {
    assert!(
        output.status.success(),
        "expected success, got status {:?}\nstdout:\n{}\nstderr:\n{}",
        output.status.code(),
        stdout(output),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn assert_contains(text: &str, needle: &str) {
    assert!(
        text.contains(needle),
        "expected output to contain {needle:?}, got:\n{text}"
    );
}

// --- Basic scan tests ---

#[test]
fn scan_basic_files_only() {
    let output = run_drail(["scan", "--scope", "src/commands", "--files", "*.rs"]);
    assert_success(&output);
    let text = stdout(&output);
    assert_contains(&text, "scan");
    assert_contains(&text, "[scope:");
    assert_contains(&text, "files (");
}

#[test]
fn scan_with_pattern_and_files() {
    let output = run_drail([
        "scan",
        "--scope",
        "src/commands",
        "--files",
        "*.rs",
        "--pattern",
        "pub fn run",
    ]);
    assert_success(&output);
    let text = stdout(&output);
    assert_contains(&text, "matches (");
    assert_contains(&text, "pub fn run");
}

#[test]
fn scan_multi_scope() {
    let output = run_drail([
        "scan",
        "--scope",
        "src/commands",
        "--scope",
        "src/output",
        "--files",
        "*.rs",
    ]);
    assert_success(&output);
    let text = stdout(&output);
    // Should have two [scope:] sections
    assert!(
        text.matches("[scope:").count() >= 2,
        "expected at least 2 scope sections, got:\n{text}"
    );
}

#[test]
fn scan_multi_pattern_ored() {
    let output = run_drail([
        "scan",
        "--scope",
        "src/commands",
        "--files",
        "*.rs",
        "--pattern",
        "pub fn run",
        "--pattern",
        "pub fn render",
    ]);
    assert_success(&output);
    let text = stdout(&output);
    assert_contains(&text, "matches (");
}

#[test]
fn scan_multi_glob() {
    let output = run_drail([
        "scan",
        "--scope",
        "src",
        "--files",
        "*.rs",
        "--files",
        "*.toml",
    ]);
    assert_success(&output);
    let text = stdout(&output);
    assert_contains(&text, "files (");
}

#[test]
fn scan_read_matching_produces_outlines() {
    let output = run_drail([
        "scan",
        "--scope",
        "src/commands",
        "--files",
        "*.rs",
        "--pattern",
        "pub fn run",
        "--read-matching",
    ]);
    assert_success(&output);
    let text = stdout(&output);
    assert_contains(&text, "read-summaries (");
    // Outlines should contain structural info like "fn" or "imports"
    assert!(
        text.contains("fn ") || text.contains("imports"),
        "expected outline content in read-summaries, got:\n{text}"
    );
}

#[test]
fn scan_json_envelope() {
    let value = run_drail_json([
        "scan",
        "--scope",
        "src/commands",
        "--files",
        "*.rs",
        "--pattern",
        "pub fn run",
        "--json",
    ]);
    assert_eq!(value["command"], "scan");
    assert_eq!(value["schema_version"], 2);
    assert_eq!(value["ok"], true);
    assert!(value["data"]["scopes"].is_array());
    assert!(value["data"]["meta"]["scopes"].as_u64().unwrap() >= 1);
    assert!(value["data"]["meta"]["total_files"].as_u64().unwrap() >= 1);
    assert!(value["data"]["meta"]["total_matches"].as_u64().unwrap() >= 1);
}

#[test]
fn scan_budget_trims_output() {
    // With a very small budget, output should be truncated
    let output = run_drail([
        "scan",
        "--scope",
        "src/commands",
        "--files",
        "*.rs",
        "--pattern",
        "pub fn run",
        "--read-matching",
        "--budget",
        "200",
    ]);
    assert_success(&output);
    let text = stdout(&output);
    // With budget=200 bytes, most content should be trimmed
    assert_contains(&text, "[scope:");
}

#[test]
fn scan_missing_scope_emits_diagnostic() {
    let output = run_drail([
        "scan",
        "--scope",
        "nonexistent_dir_that_does_not_exist_12345",
    ]);
    assert_success(&output);
    let text = stdout(&output);
    assert_contains(&text, "scope not found");
}

#[test]
fn scan_no_patterns_no_globs_lists_all_files() {
    let output = run_drail(["scan", "--scope", "src/output/json"]);
    assert_success(&output);
    let text = stdout(&output);
    assert_contains(&text, "files (");
    // Should find at least one .rs file
    assert_contains(&text, ".rs");
}

#[test]
fn scan_scopes_sorted_deterministically() {
    let output1 = run_drail([
        "scan",
        "--scope",
        "src/output",
        "--scope",
        "src/commands",
        "--files",
        "*.rs",
    ]);
    let output2 = run_drail([
        "scan",
        "--scope",
        "src/commands",
        "--scope",
        "src/output",
        "--files",
        "*.rs",
    ]);
    assert_success(&output1);
    assert_success(&output2);
    // Both should produce the same output regardless of scope order
    assert_eq!(stdout(&output1), stdout(&output2));
}
