use std::path::{Path, PathBuf};

/// Find a working bash executable.
///
/// On Windows, `Command::new("bash")` resolves to `C:\Windows\System32\bash.exe`, which
/// proxies into WSL. If the active WSL distro is minimal (e.g. docker-desktop) it has no
/// `/bin/bash`, causing tests to fail with "execvpe(/bin/bash) failed". This function
/// prefers Git bash, which is a full POSIX shell and is available on most developer machines.
pub fn bash_executable() -> PathBuf {
    #[cfg(windows)]
    {
        // Check well-known Git bash locations first.
        let candidates = [
            r"C:\Program Files\Git\bin\bash.exe",
            r"C:\Program Files\Git\usr\bin\bash.exe",
        ];
        for candidate in &candidates {
            let path = PathBuf::from(candidate);
            if path.exists() {
                return path;
            }
        }

        // Scan PATH for bash.exe, skipping WSL's stub (C:\Windows\System32\bash.exe)
        // which proxies to WSL and may not be available or functional.
        if let Ok(path_env) = std::env::var("PATH") {
            let wsl_bash = PathBuf::from(r"C:\Windows\System32\bash.exe");
            for dir in path_env.split(';') {
                let candidate = PathBuf::from(dir).join("bash.exe");
                if candidate.exists() && candidate != wsl_bash {
                    return candidate;
                }
            }
        }

        PathBuf::from("bash")
    }
    #[cfg(not(windows))]
    PathBuf::from("bash")
}

/// Convert a path to the Unix-style string that Git bash uses when given Windows paths.
///
/// Git bash maps the Windows TEMP directory to `/tmp`, and converts other drive-letter
/// paths from `C:\foo\bar` to `/c/foo/bar`. This function applies the same conversion so
/// that test assertions match script output on Windows.
///
/// On non-Windows platforms this is equivalent to `path.display().to_string()`.
pub fn bash_path(path: &Path) -> String {
    #[cfg(windows)]
    {
        let s = path.display().to_string();
        let s = s.strip_prefix(r"\\?\").unwrap_or(&s);

        // Git bash maps the Windows TEMP directory to /tmp.
        let temp = std::env::temp_dir();
        let temp_s = temp.display().to_string();
        let temp_s = temp_s.strip_prefix(r"\\?\").unwrap_or(&temp_s);
        let temp_s = temp_s.trim_end_matches('\\');
        if let Some(rest) = s.strip_prefix(temp_s) {
            let rest = rest.replace('\\', "/");
            let rest = rest.trim_start_matches('/');
            return if rest.is_empty() {
                "/tmp".to_string()
            } else {
                format!("/tmp/{rest}")
            };
        }

        // General drive-letter path: C:\foo\bar → /c/foo/bar.
        if s.len() >= 3 && s.as_bytes()[1] == b':' {
            let drive = s.chars().next().unwrap().to_ascii_lowercase();
            let rest = s[3..].replace('\\', "/");
            return format!("/{drive}/{rest}");
        }

        s.replace('\\', "/")
    }
    #[cfg(not(windows))]
    path.display().to_string()
}
