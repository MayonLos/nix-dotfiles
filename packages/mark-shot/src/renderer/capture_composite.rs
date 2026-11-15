//! 【截图】【像素合成】按逻辑区域与显示器比例合成原始截图

use super::*;
use tiny_skia::IntRect;

/// the highest scale among monitors the region touches
pub fn capture_scale(
    captures: &[crate::types::Capture],
    placements: &[crate::types::Placement],
    region: Rect,
) -> f32 {
    let max = placements
        .iter()
        .zip(captures)
        .filter(|(p, _)| {
            Rect::from_xywh(
                p.position.0 as f32,
                p.position.1 as f32,
                p.size.0 as f32,
                p.size.1 as f32,
            )
            .is_some_and(|r| crate::utils::rects_overlap(&r, &region))
        })
        .map(|(_, c)| c.scale)
        .fold(0.0_f32, f32::max);
    if max > 0.0 { max } else { 1.0 }
}

/// 【截图裁切】【精确轴比例】按覆盖 region 面积最大的显示器返回 (水平, 垂直) 物理像素/逻辑像素
///
/// 分数缩放的逻辑尺寸是取整后的整数：2560 物理宽、1.5 缩放时逻辑上报 1707，两轴的真实比例
/// 分别是 2560/1707 与 1600/1067，并不相等。只用一个标量会把完整桌面算成 2561x1601，多出
/// 一列一行透明像素；因此按捕获帧尺寸与逻辑尺寸分别给出两轴比例。
fn capture_axes(
    captures: &[crate::types::Capture],
    placements: &[crate::types::Placement],
    region: Rect,
) -> (f32, f32) {
    let mut best: Option<(f32, f32, f32)> = None;
    for (placement, capture) in placements.iter().zip(captures) {
        let Some(logical) = Rect::from_xywh(
            placement.position.0 as f32,
            placement.position.1 as f32,
            placement.size.0.max(1) as f32,
            placement.size.1.max(1) as f32,
        ) else {
            continue;
        };
        let Some(overlap) = logical.intersect(&region) else {
            continue;
        };
        let sx = capture.pixmap.width() as f32 / logical.width();
        let sy = capture.pixmap.height() as f32 / logical.height();
        if !(sx.is_finite() && sy.is_finite()) || sx <= 0.0 || sy <= 0.0 {
            continue;
        }
        let area = overlap.width() * overlap.height();
        if best.is_none_or(|(best_area, _, _)| area > best_area) {
            best = Some((area, sx, sy));
        }
    }
    best.map(|(_, sx, sy)| (sx, sy)).unwrap_or((1.0, 1.0))
}

/// 【截图裁切】【边缘吸附】按 value、逻辑量级和比例消除单精度换算误差，返回稳定边缘
///
/// 分数缩放下物理边缘常带 1e-4 级误差；先吸附到整数，再按 floor/ceil 扩展，既能覆盖
/// 分数原点的部分像素（原版 Qt 语义），又不会把完整桌面 2560/1600 算成 2561/1601。
fn snap_edge(value: f64, logical_magnitude: f64, scale: f64) -> f64 {
    let rounded = value.round();
    let tolerance = logical_magnitude.max(1.0) * scale * f64::from(f32::EPSILON) * 2.0;
    if (value - rounded).abs() <= tolerance.min(0.01) {
        rounded
    } else {
        value
    }
}

/// 【截图裁切】【像素范围】按 region、逻辑原点和两轴比例返回整像素矩形，边缘 floor/ceil 覆盖部分像素
fn pixel_rect(region: Rect, origin: (f32, f32), axes: (f32, f32)) -> Option<IntRect> {
    if !axes.0.is_finite() || !axes.1.is_finite() || axes.0 <= 0.0 || axes.1 <= 0.0 {
        return None;
    }
    let scale_x = f64::from(axes.0);
    let scale_y = f64::from(axes.1);
    let edge_x = |value: f32| {
        snap_edge(
            (f64::from(value) - f64::from(origin.0)) * scale_x,
            f64::from(value.abs().max(origin.0.abs())),
            scale_x,
        )
    };
    let edge_y = |value: f32| {
        snap_edge(
            (f64::from(value) - f64::from(origin.1)) * scale_y,
            f64::from(value.abs().max(origin.1.abs())),
            scale_y,
        )
    };
    let left = edge_x(region.left()).floor() as i32;
    let top = edge_y(region.top()).floor() as i32;
    let right = edge_x(region.right()).ceil() as i32;
    let bottom = edge_y(region.bottom()).ceil() as i32;
    IntRect::from_xywh(
        left,
        top,
        right.checked_sub(left)? as u32,
        bottom.checked_sub(top)? as u32,
    )
}

pub fn composite(
    captures: &[crate::types::Capture],
    placements: &[crate::types::Placement],
    region: Rect,
    scale: Option<f32>,
) -> Option<(Pixmap, (i32, i32), f32)> {
    let axes = scale
        .map(|value| (value, value))
        .unwrap_or_else(|| capture_axes(captures, placements, region));
    let bounds = pixel_rect(region, (0.0, 0.0), axes)?;
    if bounds.width() == 0 || bounds.height() == 0 {
        return None;
    }
    let out = compose(captures, placements, (0.0, 0.0), bounds, axes)?;
    let origin = (
        (f64::from(bounds.x()) / f64::from(axes.0)).round() as i32,
        (f64::from(bounds.y()) / f64::from(axes.1)).round() as i32,
    );
    Some((out, origin, axes.0))
}

/// 【截图裁切】【物理合成】按 captures、placements、region 和可选 scale 返回物理像素、精确全局原点及比例
pub(crate) fn composite_precise(
    captures: &[crate::types::Capture],
    placements: &[crate::types::Placement],
    region: Rect,
    scale: Option<f32>,
) -> Option<(Pixmap, (f64, f64), f32)> {
    let workspace = crate::utils::get_full_workspace_rect(placements)?;
    let region = region.intersect(&workspace)?;
    let axes = scale
        .map(|value| (value, value))
        .unwrap_or_else(|| capture_axes(captures, placements, region));
    let bounds = pixel_rect(region, (workspace.left(), workspace.top()), axes)?;
    if bounds.width() == 0 || bounds.height() == 0 {
        return None;
    }
    let origin = (
        f64::from(workspace.left()) + f64::from(bounds.x()) / f64::from(axes.0),
        f64::from(workspace.top()) + f64::from(bounds.y()) / f64::from(axes.1),
    );
    let out = compose(
        captures,
        placements,
        (workspace.left(), workspace.top()),
        bounds,
        axes,
    )?;
    Some((out, origin, axes.0))
}

/// 【截图裁切】【像素写入】按逻辑原点、整像素范围和两轴比例把 captures 合成到统一物理画布，返回缓冲
///
/// 每个显示器使用自己的捕获帧尺寸作为目标像素尺寸。完整桌面时目标矩形与源缓冲同尺寸、偏移是
/// 整数，走恒等绘制保持逐字节复制，不再因为取整差异触发一次双三次重采样。
fn compose(
    captures: &[crate::types::Capture],
    placements: &[crate::types::Placement],
    origin: (f32, f32),
    bounds: IntRect,
    axes: (f32, f32),
) -> Option<Pixmap> {
    let mut out = Pixmap::new(bounds.width(), bounds.height())?;
    let scale_x = f64::from(axes.0);
    let scale_y = f64::from(axes.1);

    for (placement, capture) in placements.iter().zip(captures) {
        let src = &capture.pixmap;
        let left =
            ((f64::from(placement.position.0) - f64::from(origin.0)) * scale_x).round() as i32;
        let top =
            ((f64::from(placement.position.1) - f64::from(origin.1)) * scale_y).round() as i32;
        let right = ((f64::from(placement.position.0 + placement.size.0) - f64::from(origin.0))
            * scale_x)
            .round() as i32;
        let bottom = ((f64::from(placement.position.1 + placement.size.1) - f64::from(origin.1))
            * scale_y)
            .round() as i32;
        let destination = ((right - left).max(0) as u32, (bottom - top).max(0) as u32);
        if destination.0 == 0 || destination.1 == 0 {
            continue;
        }
        let tx = left - bounds.x();
        let ty = top - bounds.y();
        let factor_x = destination.0 as f32 / src.width() as f32;
        let factor_y = destination.1 as f32 / src.height() as f32;
        if factor_x == 1.0 && factor_y == 1.0 {
            out.draw_pixmap(
                tx,
                ty,
                src.as_ref(),
                &tiny_skia::PixmapPaint::default(),
                Transform::identity(),
                None,
            );
        } else {
            out.draw_pixmap(
                0,
                0,
                src.as_ref(),
                &tiny_skia::PixmapPaint {
                    quality: tiny_skia::FilterQuality::Bicubic,
                    ..tiny_skia::PixmapPaint::default()
                },
                Transform::from_row(factor_x, 0.0, 0.0, factor_y, tx as f32, ty as f32),
                None,
            );
        }
    }

    Some(out)
}

#[cfg(test)]
mod tests;
