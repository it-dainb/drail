use std::ffi::OsStr;
use std::process::Output;

use assert_cmd::Command;

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

fn combined_output(output: &Output) -> String {
    format!("{}{}", stdout(output), stderr(output))
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

fn assert_failure(output: &Output) {
    assert!(
        !output.status.success(),
        "expected failure, got status {:?}\nstdout:\n{}\nstderr:\n{}",
        output.status.code(),
        stdout(output),
        stderr(output)
    );
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected to find {needle:?} in:\n{haystack}"
    );
}

#[test]
fn read_requires_path_arg() {
    let output = run_patch(["read"]);

    assert_failure(&output);
    assert_contains(&stderr(&output), "USAGE:");
}

#[test]
fn symbol_find_is_a_valid_command() {
    let output = run_patch(["symbol", "find", "main", "--scope", "src"]);

    assert_success(&output);
}

#[test]
fn help_lists_only_current_command_families() {
    let output = run_patch(["--help"]);
    let text = combined_output(&output);

    assert_success(&output);
    assert_contains(&text, "Commands:");
    assert_contains(&text, "read");
    assert_contains(&text, "symbol");
    assert_contains(&text, "search");
    assert_contains(&text, "files");
    assert_contains(&text, "deps");
    assert_contains(&text, "map");
    assert!(
        !text.contains("install") && !text.contains("mcp"),
        "expected help text to stay CLI-only, got:\n{text}"
    );
}

#[test]
fn symbol_help_lists_find_and_callers_subcommands() {
    let output = run_patch(["symbol", "--help"]);
    let text = combined_output(&output);

    assert_success(&output);
    assert_contains(&text, "find");
    assert_contains(&text, "callers");
}

#[test]
fn search_help_lists_text_and_regex_subcommands() {
    let output = run_patch(["search", "--help"]);
    let text = combined_output(&output);

    assert_success(&output);
    assert_contains(&text, "text");
    assert_contains(&text, "regex");
}

#[test]
fn bare_unknown_command_is_rejected() {
    let output = run_patch(["foo"]);

    assert_failure(&output);
    assert_contains(&stderr(&output), "unrecognized subcommand 'foo'");
}

#[test]
fn read_section_flag_is_rejected() {
    let output = run_patch(["read", "x", "--section", "1-9"]);

    assert_failure(&output);
    assert_contains(&stderr(&output), "unexpected argument '--section'");
}
