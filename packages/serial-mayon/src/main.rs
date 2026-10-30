use serial_mayon::{
    app::{self, App},
    store::Store,
    transport, tui,
};
fn main() {
    if let Err(error) = run() {
        eprintln!("serial-mayon: {error}");
        std::process::exit(1);
    }
}
fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().is_some_and(|s| s == "--help" || s == "-h") {
        println!("serial-mayon [<端口> [-b 波特率]]\nserial-mayon list\n\n无参数打开端口选择界面。? 帮助；q 退出。\n配置：$XDG_CONFIG_HOME/serial-mayon/config.json\n日志：$XDG_DATA_HOME/serial-mayon/logs/");
        return Ok(());
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
        return Ok(());
    }
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
            _ => return Err("用法：serial-mayon [<端口> [-b 波特率]] 或 serial-mayon list".into()),
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
    tui::run(app)?;
    Ok(())
}
