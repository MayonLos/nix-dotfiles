mod api;
pub mod app;
mod cleanup;
mod vm;
mod vm_xml;
use cleanup::{Entry, Kind};
use std::{io, io::Write};

const HELP: &str = "mayon-tools docker 0.2.0

--host unix:///path/docker.sock  Docker socket (overrides DOCKER_HOST)
--help · --version

无子命令：TUI，1 容器 · 2 镜像 · 3 卷 · 4 概览 · 5 清理 · ? 帮助

df                              Docker + VM 只读空间总览与明细
clean --image ID --container ID --cache ID --volume NAME [--yes]
  可重复指定完整 ID/卷名；不支持全清，卷必须显式指定名字。
  默认仅预览准确清单。执行必须 --yes，预览后输入 DELETE 再确认。
  含卷还需单独输入 DELETE 与所有完整卷名；卷数据不可恢复。
  运行中容器、被引用的镜像/卷、Shared/InUse 缓存不可清理。\n\n5 空间面板 Tab/v 切换 Docker / VM · VM 严格只读，Enter 详情/y 复制路径。\nVM 查询 qemu:///session 与 qemu:///system；绝不删除 VM、镜像、快照或 ISO。";

#[derive(Debug, Default)]
struct Args {
    host: Option<String>,
    command: Option<String>,
    targets: Vec<(Kind, String)>,
    yes: bool,
}
fn parse_args(args: impl IntoIterator<Item = String>) -> Result<Args, String> {
    let mut parsed = Args::default();
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--host" => parsed.host = Some(args.next().ok_or("--host requires unix:// endpoint")?),
            "df" | "clean" if parsed.command.is_none() => parsed.command = Some(arg),
            "--yes" => parsed.yes = true,
            "--image" | "--container" | "--cache" | "--volume" => {
                let kind = match arg.as_str() {
                    "--image" => Kind::Image,
                    "--container" => Kind::Container,
                    "--cache" => Kind::Cache,
                    _ => Kind::Volume,
                };
                let id = args
                    .next()
                    .filter(|s| !s.is_empty() && !s.starts_with('-'))
                    .ok_or("选择器需要完整 ID / 卷名")?;
                if !parsed.targets.contains(&(kind, id.clone())) {
                    parsed.targets.push((kind, id));
                }
            }
            _ => return Err("unknown argument; use --help".into()),
        }
    }
    if parsed.command.as_deref() != Some("clean") && (parsed.yes || !parsed.targets.is_empty()) {
        return Err("--yes 与资源选择器仅用于 clean".into());
    }
    if parsed.command.as_deref() == Some("clean") && parsed.targets.is_empty() {
        return Err("clean 需要明确 ID / 卷名；不提供一键全清".into());
    }
    Ok(parsed)
}
fn plan_for(entries: &[Entry], targets: &[(Kind, String)]) -> Result<Vec<Entry>, String> {
    targets
        .iter()
        .map(|(kind, id)| {
            entries
                .iter()
                .find(|e| e.kind == *kind && e.id == *id && e.selectable())
                .cloned()
                .ok_or_else(|| format!("不可清理或不存在：{} {id}", kind.label()))
        })
        .collect()
}
fn confirm_input(prompt: &str, expected: &str) -> io::Result<bool> {
    print!("{prompt}\n> ");
    io::stdout().flush()?;
    let mut value = String::new();
    io::stdin().read_line(&mut value)?;
    Ok(value.trim_end_matches(['\r', '\n']) == expected)
}
pub async fn command(args: Vec<String>) -> Result<bool, Box<dyn std::error::Error>> {
    // These are intentionally resolved before constructing an Engine or terminal.
    if args.iter().any(|a| a == "--help" || a == "-h") {
        println!("{HELP}");
        return Ok(true);
    }
    if args.iter().any(|a| a == "--version") {
        println!("mayon-tools docker 0.2.0");
        return Ok(true);
    }
    let args = parse_args(args).map_err(io::Error::other)?;
    if let Some(command) = args.command {
        let host = args.host.or_else(|| std::env::var("DOCKER_HOST").ok());
        if command == "df" {
            let docker = async {
                let engine = api::Engine::new(host)?;
                engine.disk().await
            };
            let (disk, vm) = tokio::join!(docker, vm::collect());
            match disk {
                Ok(disk) => {
                    println!(
                        "{}\n\nDocker 明细（占用降序；锁定项不可选）：",
                        cleanup::summary(&disk)
                    );
                    for entry in cleanup::entries(&disk) {
                        println!(
                            "{}\n{}\n",
                            entry.description(),
                            entry.blocked.as_deref().unwrap_or("可清理（卷默认不选）")
                        );
                    }
                }
                Err(reason) => println!("Docker 不可用：{reason}"),
            }
            println!("\n{}", vm.cli());
        } else {
            let engine = api::Engine::new(host).map_err(io::Error::other)?;
            let disk = engine.disk().await.map_err(io::Error::other)?;
            let entries = cleanup::entries(&disk);
            let plan = plan_for(&entries, &args.targets).map_err(io::Error::other)?;
            println!("准确删除清单（预计释放 {}）：", cleanup::estimate(&plan));
            for entry in &plan {
                println!("{}\n", entry.description());
            }
            io::stdout().flush()?;
            if !args.yes {
                println!("仅预览；未执行。执行需要显式 --yes 和预览后二次确认。");
                return Ok(true);
            }
            if !confirm_input(
                "二次确认：输入 DELETE 执行以上清单（Esc / 其它输入取消）",
                "DELETE",
            )? {
                println!("已取消；未执行");
                return Ok(true);
            }
            let volumes: Vec<_> = plan
                .iter()
                .filter(|e| e.kind == Kind::Volume)
                .map(|e| e.id.as_str())
                .collect();
            if !volumes.is_empty() {
                let phrase = format!("DELETE {}", volumes.join(" "));
                if !confirm_input(
                    &format!("卷数据不可恢复！另行输入完整文本：{phrase}"),
                    &phrase,
                )? {
                    println!("已取消；未执行");
                    return Ok(true);
                }
            }
            let report = cleanup::execute(&engine, &plan).await;
            println!("{}", report.body());
            if report.failed > 0 {
                return Err(io::Error::other("部分项目清理失败；见上方准确清单").into());
            }
        }
        return Ok(true);
    }
    Ok(false)
}
pub fn host(args: &[String]) -> Result<Option<String>, String> {
    Ok(parse_args(args.to_owned())?.host)
}
#[cfg(test)]
mod cli_tests {
    use super::*;
    fn args(s: &str) -> Result<Args, String> {
        parse_args(s.split_whitespace().map(String::from))
    }
    #[test]
    fn no_blanket_cleanup_and_read_only_df() {
        assert!(args("clean --yes").is_err());
        assert!(args("df --yes").is_err());
        assert!(args("df --volume data").is_err());
        assert!(args("--yes").is_err());
        assert!(args("clean --image abc --volume").is_err());
        assert!(!args("clean --image abc").unwrap().yes);
        assert_eq!(
            args("clean --yes --image abc --image abc")
                .unwrap()
                .targets
                .len(),
            1
        );
        assert_eq!(
            args("clean --yes --volume data").unwrap().targets,
            [(Kind::Volume, "data".into())]
        );
    }
}
