//! Automatic paste after a clipboard selection.
//!
//! Mango (like every wlroots compositor with the virtual-keyboard protocol)
//! accepts synthetic key events through `zwp_virtual_keyboard_manager_v1`.
//! `wtype` is the small, standard client for that protocol, so the overlay
//! spawns it after the layer surface is destroyed and the compositor has
//! returned keyboard focus to the previously focused toplevel.
//!
//! If the compositor does not expose the protocol (or the chord cannot be
//! delivered), this degrades to "copied, notification only" and records the
//! exact reason from wtype's stderr in the log and the notification body.

use crate::logger::{json_string, Logger};
use std::process::{Command, Stdio};
use std::thread::sleep;
use std::time::Duration;

/// Delay between destroying the overlay and injecting the chord. Keyboard
/// focus returns to the previous toplevel when the layer surface is destroyed;
/// injecting in the same millisecond would race that focus change.
const FOCUS_SETTLE: Duration = Duration::from_millis(160);

pub struct PasteOutcome {
    pub injected: bool,
    pub command: String,
    pub reason: Option<String>,
}

/// Resolve a human-readable chord into wtype arguments.
fn chord_arguments(chord: &str) -> Option<Vec<String>> {
    let chord = chord.trim();
    if chord.is_empty() || chord == "none" {
        return None;
    }
    let mut modifiers = Vec::new();
    let mut key = None;
    for part in chord.split('+') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        match part.to_lowercase().as_str() {
            "ctrl" | "control" => modifiers.push("ctrl"),
            "shift" => modifiers.push("shift"),
            "alt" => modifiers.push("alt"),
            "super" | "mod4" | "meta" => modifiers.push("logo"),
            other => key = Some(other.to_string()),
        }
    }
    let key = key?;
    let mut args = Vec::new();
    for modifier in &modifiers {
        args.push("-M".to_string());
        args.push((*modifier).to_string());
    }
    args.push("-k".to_string());
    args.push(key);
    for modifier in modifiers.into_iter().rev() {
        args.push("-m".to_string());
        args.push(modifier.to_string());
    }
    Some(args)
}

pub fn inject(chord: &str, logger: &Logger) -> PasteOutcome {
    let command = format!("wtype {}", chord);
    let Some(arguments) = chord_arguments(chord) else {
        return PasteOutcome {
            injected: false,
            command,
            reason: Some("paste chord disabled by configuration".to_string()),
        };
    };
    sleep(FOCUS_SETTLE);
    let output = Command::new("wtype")
        .args(&arguments)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output();
    match output {
        Ok(output) if output.status.success() => PasteOutcome {
            injected: true,
            command,
            reason: None,
        },
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let reason = if !stderr.is_empty() {
                stderr
            } else if !stdout.is_empty() {
                stdout
            } else {
                format!("wtype exited with {}", output.status)
            };
            logger.event(
                "paste_failed",
                &[
                    ("command", json_string(&command)),
                    ("reason", json_string(&reason)),
                ],
            );
            PasteOutcome {
                injected: false,
                command,
                reason: Some(reason),
            }
        }
        Err(error) => {
            let reason = format!("cannot run wtype: {}", error);
            logger.event(
                "paste_failed",
                &[
                    ("command", json_string(&command)),
                    ("reason", json_string(&reason)),
                ],
            );
            PasteOutcome {
                injected: false,
                command,
                reason: Some(reason),
            }
        }
    }
}

/// Show a desktop notification after a degraded copy. Best effort: in a
/// headless test session there is no notification daemon, and that is logged
/// rather than treated as a failure of the overlay.
pub fn notify_copy(title: &str, body: &str, logger: &Logger) {
    let status = Command::new("notify-send")
        .args(["-a", "mayon-overlay", "-i", "edit-paste", title, body])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .output();
    match status {
        Ok(output) if output.status.success() => {
            logger.event("notify", &[("ok", "true".to_string())]);
        }
        Ok(output) => {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            logger.event(
                "notify",
                &[
                    ("ok", "false".to_string()),
                    ("reason", json_string(&stderr)),
                ],
            );
        }
        Err(error) => {
            logger.event(
                "notify",
                &[
                    ("ok", "false".to_string()),
                    ("reason", json_string(&error.to_string())),
                ],
            );
        }
    }
}
