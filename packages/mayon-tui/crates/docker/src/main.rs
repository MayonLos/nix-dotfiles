mod api;
mod app;
use app::App;
use crossterm::event::{self, Event, KeyEventKind};
use std::{io, time::Duration};
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let mut host = None;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--help" | "-h" => {
                println!(
                    "dockertui-mayon 0.2.0\n\n--host unix:///path/docker.sock  Docker Engine socket (overrides DOCKER_HOST)\n--version\n\n1 containers · 2 images · 3 volumes · 4 overview · ? help"
                );
                return Ok(());
            }
            "--version" => {
                println!("dockertui-mayon 0.2.0");
                return Ok(());
            }
            "--host" => host = Some(args.next().ok_or("--host requires unix:// endpoint")?),
            _ => return Err(io::Error::other("unknown argument; use --help").into()),
        }
    }
    let mut app = App::new(host).map_err(io::Error::other)?;
    let (mut terminal, _guard) = mayon_ui::terminal()?;
    while !app.quit {
        app.tick();
        terminal.draw(|f| app.draw(f))?;
        if event::poll(Duration::from_millis(70))? {
            match event::read()? {
                Event::Key(k) if k.kind != KeyEventKind::Release => app.key(k),
                Event::Mouse(m) => app.mouse(m, terminal.size()?),
                _ => {}
            }
        }
        tokio::task::yield_now().await;
    }
    Ok(())
}
