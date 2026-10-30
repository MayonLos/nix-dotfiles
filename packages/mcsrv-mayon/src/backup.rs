use crate::{model::*, runtime};
use anyhow::{bail, Context, Result};
use std::{
    fs,
    path::Path,
    process::{Command, Output},
};
fn restic(dir: &Path) -> Result<Command> {
    let backups = dir.join("backups");
    private_dir(&backups)?;
    let password = backups.join("password");
    no_symlinks(&password)?;
    if !password.exists() {
        write_private(&password, random_secret().as_bytes())?;
    }
    no_symlinks(&backups.join("repo"))?;
    let mut cmd = Command::new("restic");
    parent_death_signal(&mut cmd);
    cmd.current_dir(dir)
        .arg("--repo")
        .arg(backups.join("repo"))
        .arg("--password-file")
        .arg(password);
    Ok(cmd)
}
fn checked(output: Output) -> Result<String> {
    if !output.status.success() {
        bail!("restic 失败: {}", String::from_utf8_lossy(&output.stderr));
    }
    Ok(String::from_utf8(output.stdout)?)
}
fn init(dir: &Path) -> Result<()> {
    if !dir.join("backups/repo/config").exists() {
        checked(
            restic(dir)?
                .arg("init")
                .output()
                .context("需安装 restic（Nix wrapper 提供）")?,
        )?;
    }
    Ok(())
}
pub fn snapshots(root: &Path, name: &str) -> Result<String> {
    let dir = instance(root, name)?;
    load(root, name)?;
    if !dir.join("backups/repo/config").exists() {
        return Ok("[]".into());
    }
    checked(restic(&dir)?.args(["snapshots", "--json"]).output()?)
}
pub fn backup(root: &Path, name: &str) -> Result<String> {
    let dir = instance(root, name)?;
    let _op = lock(&dir, "operation.lock")?;
    perform(root, name, running(&dir))
}
pub fn backup_stopped(root: &Path, name: &str) -> Result<String> {
    let dir = instance(root, name)?;
    let _op = lock(&dir, "operation.lock")?;
    perform(root, name, false)
}
struct Saving<'a> {
    root: &'a Path,
    name: &'a str,
    active: bool,
}
impl Drop for Saving<'_> {
    fn drop(&mut self) {
        if self.active {
            if let Err(e) = runtime::command(self.root, self.name, "@save-on") {
                eprintln!("自动保存恢复失败，请立即在控制台执行 save-on: {e:#}");
            }
        }
    }
}
fn perform(root: &Path, name: &str, live: bool) -> Result<String> {
    let dir = instance(root, name)?;
    let c = load(root, name)?;
    let world_names = worlds(&dir)?;
    if world_names.is_empty() {
        return Ok("尚无世界；首次启动无需备份".into());
    }
    init(&dir)?;
    let mut saving = Saving {
        root,
        name,
        active: false,
    };
    if live {
        // Even a missing acknowledgement can mean save-off took effect. Always attempt save-on.
        saving.active = true;
        runtime::command(root, name, "@save-off")?;
        runtime::command(
            root,
            name,
            if c.version.starts_with("1.7.") || c.kind == "gtnh" {
                "@save-all"
            } else {
                "@save-all-flush"
            },
        )?;
    }
    // Back up only world trees. Passwords, logs, launchers and user credentials stay outside.
    let output = checked(
        restic(&dir)?
            .args(["backup", "--json", "--tag", "mcsrv-worlds"])
            .args(&world_names)
            .output()?,
    )?;
    if live {
        runtime::command(root, name, "@save-on")
            .context("快照已创建，但自动保存恢复未获确认；请检查控制台并执行 save-on")?;
        saving.active = false;
    }
    drop(saving);
    // Keep data chunks until an explicit owner-run prune. Forget affects snapshots, never live worlds.
    checked(
        restic(&dir)?
            .args([
                "forget",
                "--tag",
                "mcsrv-worlds",
                "--group-by",
                "",
                "--keep-last",
                &c.keep_last.to_string(),
            ])
            .output()?,
    )?;
    Ok(output)
}
pub fn restore(root: &Path, name: &str, snapshot: &str, confirm: &str) -> Result<()> {
    if snapshot != confirm
        || snapshot.len() < 8
        || snapshot.len() > 64
        || !snapshot.bytes().all(|b| b.is_ascii_hexdigit())
    {
        bail!("回滚需 --confirm 同一完整/短快照ID（至少8位hex）");
    }
    let dir = instance(root, name)?;
    let _op = lock(&dir, "operation.lock")?;
    let _run = lock(&dir, "run.lock").context("回滚前必须先停止服务器")?;
    let available: serde_json::Value = serde_json::from_str(&snapshots(root, name)?)?;
    let candidates: Vec<_> = available
        .as_array()
        .context("快照列表格式错误")?
        .iter()
        .filter(|s| s["id"].as_str().is_some_and(|id| id.starts_with(snapshot)))
        .collect();
    if candidates.len() != 1 {
        bail!("快照不存在或ID不唯一");
    }
    let full = candidates[0]["id"].as_str().context("快照缺少ID")?;
    // Snapshot selection happens before making another backup, so retention cannot change its meaning.
    let staging = tempfile::Builder::new()
        .prefix(".restore-")
        .tempdir_in(&dir)?;
    checked(
        restic(&dir)?
            .arg("restore")
            .arg(full)
            .arg("--target")
            .arg(staging.path())
            .output()?,
    )?;
    let mut restored = Vec::new();
    for e in fs::read_dir(staging.path())? {
        let e = e?;
        let name = e.file_name().to_string_lossy().into_owned();
        valid_name(&name)?;
        if !e.file_type()?.is_dir() {
            bail!("快照包含非世界顶层对象，拒绝回滚");
        }
        restored.push(name);
    }
    if restored.is_empty() {
        bail!("快照中没有世界");
    }
    // Every restored entry must be a current world (including temporarily missing dimensions).
    let props = fs::read_to_string(dir.join("server.properties"))?;
    let level = props
        .lines()
        .find_map(|l| l.strip_prefix("level-name="))
        .unwrap_or("world");
    valid_name(level)?;
    let allowed = [
        level.to_owned(),
        format!("{level}_nether"),
        format!("{level}_the_end"),
    ];
    if restored.iter().any(|n| !allowed.contains(n)) {
        bail!("快照目录与当前 level-name 不一致，拒绝回滚");
    }
    fn validate_tree(path: &Path) -> Result<()> {
        for e in fs::read_dir(path)? {
            let e = e?;
            let t = e.file_type()?;
            if t.is_symlink() || (!t.is_file() && !t.is_dir()) {
                bail!("快照含链接/特殊文件，拒绝回滚");
            }
            if t.is_dir() {
                validate_tree(&e.path())?;
            }
        }
        Ok(())
    }
    validate_tree(staging.path())?;
    perform(root, name, false).context("回滚前备份失败，未改当前世界")?;
    let recovery = dir.join("rollback-preserved").join(format!(
        "{}-{}",
        chrono::Utc::now().format("%Y%m%dT%H%M%S"),
        rand::random::<u32>()
    ));
    private_dir(&recovery)?;
    // Preserve all current dimensions, including dimensions absent from the selected older snapshot.
    let mut moved = Vec::new();
    for n in &allowed {
        if dir.join(n).exists() {
            no_symlinks(&dir.join(n))?;
            fs::rename(dir.join(n), recovery.join(n))?;
            moved.push(n.clone());
        }
    }
    let mut installed = Vec::new();
    for n in &restored {
        if let Err(e) = fs::rename(staging.path().join(n), dir.join(n)) {
            for done in &installed {
                let _ = fs::rename(dir.join(done), staging.path().join(done));
            }
            for old in &moved {
                let _ = fs::rename(recovery.join(old), dir.join(old));
            }
            return Err(e).context("回滚安装失败，已尝试复原；请检查 rollback-preserved");
        }
        installed.push(n.clone());
    }
    println!(
        "已恢复 {full}；原世界保留在 {}，不会自动删除",
        recovery.display()
    );
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn restore_requires_exact_confirmation() {
        assert!(restore(Path::new("/tmp"), "test", "deadbeef", "wrong").is_err());
        assert!(restore(Path::new("/tmp"), "test", "latest", "latest").is_err());
    }
}
