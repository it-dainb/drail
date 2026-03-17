use std::io::Write;
use std::process;

pub fn emit(output: &str, is_tty: bool) {
    let line_count = output.lines().count();

    if is_tty && line_count > terminal_height() {
        let pager = std::env::var("PAGER").unwrap_or_else(|_| "less".into());
        if let Ok(mut child) = process::Command::new(&pager)
            .arg("-R")
            .stdin(process::Stdio::piped())
            .spawn()
        {
            if let Some(mut stdin) = child.stdin.take() {
                let _ = stdin.write_all(output.as_bytes());
            }
            let _ = child.wait();
            return;
        }
    }

    println!("{output}");
}

fn terminal_height() -> usize {
    std::env::var("LINES")
        .ok()
        .and_then(|lines| lines.parse::<usize>().ok())
        .unwrap_or(24)
}
