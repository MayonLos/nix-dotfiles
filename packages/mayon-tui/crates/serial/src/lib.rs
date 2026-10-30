pub mod app;
pub mod codec;
pub mod flash;
pub mod store;
pub mod transport;
pub mod tui;

use app::App;
use store::Store;
pub fn command(args: &[String]) -> Result<bool, Box<dyn std::error::Error>> {
    if args.first().is_some_and(|s| s == "--help" || s == "-h") {
        println!("mayon-tools serial [<端口> [-b 波特率]]\nmayon-tools serial list\n配置和日志仍在 serial-mayon 的原目录。");
        return Ok(true);
    }
    if args.first().is_some_and(|s| s == "list") {
        if args.len() != 1 {
            return Err("list 不接受额外参数".into());
        }
        println!("端口\tVID:PID\t产品\t序列号\t接口");
        for d in transport::discover() {
            println!(
                "{}\t{:04x}:{:04x}\t{}\t{}\t{}",
                d.path,
                d.vid,
                d.pid,
                d.product,
                d.serial.as_deref().unwrap_or("无"),
                d.interface
            );
        }
        return Ok(true);
    }
    validate_args(args)?;
    Ok(false)
}
fn validate_args(args: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    let mut i = 0;
    let mut port = false;
    while i < args.len() {
        match args[i].as_str() {
            "-b" | "--baud" => {
                i += 1;
                let n = args.get(i).ok_or("-b 缺少波特率")?.parse::<u32>()?;
                if n == 0 || n > 12_000_000 {
                    return Err("波特率范围 1–12000000".into());
                }
            }
            s if !s.starts_with('-') && !port => port = true,
            _ => return Err("无效串口参数".into()),
        };
        i += 1;
    }
    Ok(())
}
pub fn open(args: &[String]) -> Result<App, Box<dyn std::error::Error>> {
    let mut port = None;
    let mut baud = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-b" | "--baud" => {
                i += 1;
                let value = args.get(i).ok_or("-b 缺少波特率")?.parse::<u32>()?;
                if value == 0 || value > 12_000_000 {
                    return Err("波特率范围 1–12000000".into());
                }
                baud = Some(value);
            }
            arg if !arg.starts_with('-') && port.is_none() => port = Some(arg.to_owned()),
            _ => {
                return Err(
                    "用法：mayon-tools serial [<端口> [-b 波特率]] 或 mayon-tools serial list"
                        .into(),
                )
            }
        }
        i += 1;
    }
    let mut app = App::new(Store::load()?);
    if let Some(path) = port {
        let device = app
            .devices
            .iter()
            .find(|d| d.path == path)
            .cloned()
            .or_else(|| {
                std::fs::canonicalize(&path).ok().and_then(|resolved| {
                    app.devices
                        .iter()
                        .find(|d| std::path::Path::new(&d.path) == resolved)
                        .cloned()
                })
            })
            .unwrap_or_else(|| app::explicit_device(path));
        app.select(device, baud);
    } else if let Some(baud) = baud {
        app.profile.settings.baud = baud;
    }
    Ok(app)
}
