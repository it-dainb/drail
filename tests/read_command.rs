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
fn read_path_renders_file_contents() {
    let output = run_patch(["read", "src/commands/read.rs"]);

    assert_success(&output);
    assert_contains(&stdout(&output), "pub fn run(args: &ReadArgs)");
}

#[test]
fn read_lines_renders_only_requested_range() {
    let output = run_patch(["read", "README.md", "--lines", "1:5"]);
    let text = stdout(&output);

    assert_success(&output);
    assert_contains(&text, "1 │ # patch");
    assert_contains(&text, "5 │ The product goal is simple");
    assert!(
        !text.contains("## Command families"),
        "expected later README content to be excluded, got:\n{text}"
    );
}

#[test]
fn read_heading_renders_markdown_section() {
    let output = run_patch(["read", "README.md", "--heading", "## Installation"]);
    let text = stdout(&output);

    assert_success(&output);
    assert_contains(&text, "## Installation");
    assert_contains(&text, "./install.sh --dry-run");
    assert!(
        !text.contains("## Build and test"),
        "expected section to stop before next top-level heading, got:\n{text}"
    );
}

#[test]
fn read_rejects_lines_and_heading_together() {
    let output = run_patch([
        "read",
        "README.md",
        "--lines",
        "1:4",
        "--heading",
        "## Installation",
    ]);

    assert_failure(&output);
    assert_contains(&stderr(&output), "cannot be used with");
}

#[test]
fn read_rejects_heading_for_non_markdown_files() {
    let output = run_patch([
        "read",
        "src/commands/read.rs",
        "--heading",
        "## Installation",
    ]);

    assert_failure(&output);
    assert_contains(&stderr(&output), "heading");
    assert_contains(&stderr(&output), "markdown");
}
