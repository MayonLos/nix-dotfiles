//! Script entrypoints use the same transactions as the TUI. URLs enter via stdin, never argv.
use crate::{api::Client, native::Native};
use std::{io::Read, path::PathBuf};
pub async fn run() -> Result<bool, String> {
    let raw: Vec<String> = std::env::args().skip(1).collect();
    if !raw
        .first()
        .is_some_and(|s| matches!(s.as_str(), "profile" | "settings" | "service"))
    {
        return Ok(false);
    }
    let home = PathBuf::from(std::env::var_os("HOME").ok_or("缺少 HOME")?);
    let mut ctx = Native {
        data: home.join(".local/share/mayon-clash"),
        socket: "/run/mayon-clash/mihomo.sock".into(),
        verge_profiles: home
            .join(".local/share/io.github.clash-verge-rev.clash-verge-rev/profiles.yaml"),
        mihomo: "mihomo".into(),
        systemctl: "systemctl".into(),
        yq: "yq".into(),
    };
    let mut args = vec![];
    let mut iter = raw.into_iter();
    while let Some(a) = iter.next() {
        match a.as_str() {
            "--data-dir" => ctx.data = iter.next().ok_or("缺少目录")?.into(),
            "--socket" => ctx.socket = iter.next().ok_or("缺少 socket")?.into(),
            "--profiles" => ctx.verge_profiles = iter.next().ok_or("缺少 Verge 索引路径")?.into(),
            "--mihomo" => ctx.mihomo = iter.next().ok_or("缺少命令")?.into(),
            "--systemctl" => ctx.systemctl = iter.next().ok_or("缺少命令")?.into(),
            _ => args.push(a),
        }
    }
    let running = Client::new(ctx.socket.clone())
        .map_err(|_| "控制接口无效")?
        .version()
        .await
        .is_ok();
    let get = |i: usize| {
        args.get(i)
            .map(String::as_str)
            .ok_or("缺少参数".to_string())
    };
    match (get(0)?, get(1)?) {
        ("profile", "add") => {
            ctx.add(
                &stdin_url()?,
                args.get(2).map(String::as_str).unwrap_or(""),
                running,
            )
            .await?
        }
        ("profile", "list") => {
            for s in ctx.store()?.items {
                println!("{}\t{}", s.id, s.name);
            }
        }
        ("profile", "update") => {
            let id = get(2)?;
            if id == "all" {
                for s in ctx.store()?.items {
                    ctx.update(&s.id, running, None).await?;
                }
            } else {
                ctx.update(id, running, None).await?;
            }
        }
        ("profile", "use") => ctx.select(get(2)?, running).await?,
        ("profile", "rename") => ctx.rename(get(2)?, get(3)?).await?,
        ("profile", "url") => ctx.update(get(2)?, running, Some(&stdin_url()?)).await?,
        ("profile", "delete") => {
            if get(3)? != "--yes" {
                return Err("删除需要 --yes；当前订阅不可删除".into());
            }
            ctx.delete(get(2)?)?;
        }
        ("profile", "import-verge") => println!("{}", ctx.import_verge(running).await?),
        ("profile", "generate") => ctx.generate().await?,
        ("settings", key) => ctx.change(key, get(2)?, running).await?,
        ("service", "start") => {
            ctx.generate().await?;
            ctx.service("start").await?;
        }
        ("service", "stop") => ctx.service("stop").await?,
        _ => return Err("非交互命令无效，参见 README".into()),
    }
    Ok(true)
}
fn stdin_url() -> Result<String, String> {
    let mut raw = String::new();
    std::io::stdin()
        .take(16385)
        .read_to_string(&mut raw)
        .map_err(|_| "无法读取 URL")?;
    if raw.len() > 16384 {
        return Err("URL 过长".into());
    }
    Ok(raw.trim().to_string())
}
