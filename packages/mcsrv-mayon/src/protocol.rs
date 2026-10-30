//! Bounded Minecraft status handshake; no login, account or world interaction.
use anyhow::{bail, Context, Result};
use std::{
    io::{Read, Write},
    net::{SocketAddr, TcpStream},
    time::Duration,
};
fn varint(mut value: u32) -> Vec<u8> {
    let mut out = Vec::new();
    loop {
        let mut b = (value & 127) as u8;
        value >>= 7;
        if value > 0 {
            b |= 128;
        }
        out.push(b);
        if value == 0 {
            return out;
        }
    }
}
fn read_varint(reader: &mut impl Read) -> Result<u32> {
    let mut value = 0;
    for shift in (0..35).step_by(7) {
        let mut b = [0];
        reader.read_exact(&mut b)?;
        if shift == 28 && b[0] > 15 {
            bail!("status VarInt 溢出");
        }
        value |= ((b[0] & 127) as u32) << shift;
        if b[0] & 128 == 0 {
            return Ok(value);
        }
    }
    bail!("status VarInt 太长")
}
pub fn status(port: u16, legacy: bool, bind: &str) -> Result<serde_json::Value> {
    let ip: std::net::IpAddr = match bind {
        "" | "0.0.0.0" => "127.0.0.1",
        "::" => "::1",
        other => other,
    }
    .parse()?;
    let address = SocketAddr::new(ip, port);
    let host = ip.to_string();
    let mut socket = TcpStream::connect_timeout(&address, Duration::from_secs(2))?;
    socket.set_read_timeout(Some(Duration::from_secs(2)))?;
    socket.set_write_timeout(Some(Duration::from_secs(2)))?;
    let mut handshake = vec![0];
    handshake.extend(varint(if legacy { 5 } else { 769 }));
    handshake.extend(varint(host.len() as u32));
    handshake.extend(host.as_bytes());
    handshake.extend(port.to_be_bytes());
    handshake.push(1);
    socket.write_all(&varint(handshake.len() as u32))?;
    socket.write_all(&handshake)?;
    socket.write_all(&[1, 0])?;
    let size = read_varint(&mut socket)? as usize;
    if size > 1024 * 1024 {
        bail!("status 响应超限");
    }
    let mut bytes = vec![0; size];
    socket.read_exact(&mut bytes)?;
    let mut cursor = std::io::Cursor::new(bytes);
    if read_varint(&mut cursor)? != 0 {
        bail!("status 包类型无效");
    }
    let n = read_varint(&mut cursor)? as usize;
    if n > size.saturating_sub(cursor.position() as usize) {
        bail!("status 字符串长度无效");
    }
    let mut text = vec![0; n];
    cursor.read_exact(&mut text)?;
    serde_json::from_slice(&text).context("status JSON 无效")
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn varint_bounds() {
        for n in [0, 1, 127, 128, 255, u32::MAX] {
            assert_eq!(read_varint(&mut &varint(n)[..]).unwrap(), n);
        }
        assert!(read_varint(&mut &[0xff, 0xff, 0xff, 0xff, 0x10][..]).is_err());
    }
}
