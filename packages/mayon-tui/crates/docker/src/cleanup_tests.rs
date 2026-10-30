use super::*;
use crossterm::event::KeyCode;
use std::collections::HashSet;

fn disk(value: Value) -> Disk {
    serde_json::from_value(value).expect("fixture decodes as Docker disk usage")
}

fn entry(kind: Kind, id: &str, reclaim: Option<u64>) -> Entry {
    Entry {
        kind,
        id: id.into(),
        name: id.into(),
        size: reclaim,
        reclaim,
        blocked: None,
    }
}

#[test]
fn running_paused_restarting_unknown_and_missing_states_are_locked() {
    let snapshot = disk(serde_json::json!({
        "Containers": [
            {"Id":"running", "State":"running", "SizeRw":10},
            {"Id":"paused", "State":"paused", "SizeRw":20},
            {"Id":"restarting", "State":"restarting", "SizeRw":30},
            {"Id":"unknown", "State":"removing", "SizeRw":40},
            {"Id":"missing", "SizeRw":50},
            {"Id":"stopped", "State":"exited", "SizeRw":60}
        ]
    }));

    let rows: Vec<_> = entries(&snapshot)
        .into_iter()
        .filter(|row| row.kind == Kind::Container)
        .map(|row| {
            let selectable = row.selectable();
            (row.id, selectable)
        })
        .collect();
    assert_eq!(
        rows,
        [
            ("stopped".into(), true),
            ("missing".into(), false),
            ("unknown".into(), false),
            ("restarting".into(), false),
            ("paused".into(), false),
            ("running".into(), false),
        ]
    );
}

#[test]
fn image_and_volume_reference_lists_override_zero_refcounts() {
    let snapshot = disk(serde_json::json!({
        "Images": [
            {"Id":"sha256:used", "Containers":0, "Size":100, "SharedSize":0, "RepoTags":["used:1"]},
            {"Id":"sha256:free", "Containers":0, "Size":80, "SharedSize":0, "RepoTags":["free:1"]}
        ],
        "Containers": [{
            "Id":"stopped", "ImageID":"sha256:used", "State":"exited", "SizeRw":1,
            "Mounts":[{"Type":"volume", "Name":"mounted-zero-ref"}]
        }],
        "Volumes": [
            {"Name":"mounted-zero-ref", "UsageData":{"Size":50, "RefCount":0}},
            {"Name":"truly-free", "UsageData":{"Size":40, "RefCount":0}}
        ]
    }));
    let rows = entries(&snapshot);
    let image = rows
        .iter()
        .find(|row| row.kind == Kind::Image && row.id == "sha256:used")
        .unwrap();
    assert!(
        !image.selectable(),
        "an ImageID reference protects the image even when Containers is zero"
    );
    assert!(rows
        .iter()
        .find(|row| row.kind == Kind::Image && row.id == "sha256:free")
        .unwrap()
        .selectable());
    let mounted = rows
        .iter()
        .find(|row| row.kind == Kind::Volume && row.id == "mounted-zero-ref")
        .unwrap();
    assert!(
        !mounted.selectable(),
        "Mounts protects the volume even when RefCount is zero"
    );
    assert!(rows
        .iter()
        .find(|row| row.kind == Kind::Volume && row.id == "truly-free")
        .unwrap()
        .selectable());
}

#[test]
fn unknown_reference_data_fails_closed_and_no_rows_are_selected_by_default() {
    let snapshot = disk(serde_json::json!({
        "Images": [
            {"Id":"sha256:unknown-count", "Size":10, "RepoTags":["unknown:1"]},
            {"Id":"sha256:unknown-shared", "Containers":0, "Size":20, "SharedSize":-1, "RepoTags":["unknown-shared:1"]}
        ],
        "Volumes": [
            {"Name":"unknown-refs", "UsageData":{"Size":100}},
            {"Name":"unknown-size", "UsageData":{"RefCount":0}}
        ]
    }));
    let rows = entries(&snapshot);
    assert!(!rows
        .iter()
        .find(|row| row.id == "sha256:unknown-count")
        .unwrap()
        .selectable());
    assert!(rows
        .iter()
        .find(|row| row.id == "sha256:unknown-shared")
        .unwrap()
        .selectable());
    assert!(!rows
        .iter()
        .find(|row| row.id == "unknown-refs")
        .unwrap()
        .selectable());
    assert!(rows
        .iter()
        .find(|row| row.id == "unknown-size")
        .unwrap()
        .selectable());
    assert_eq!(
        rows.iter()
            .find(|row| row.id == "sha256:unknown-shared")
            .unwrap()
            .reclaim,
        None
    );
    assert_eq!(
        rows.iter()
            .find(|row| row.id == "unknown-size")
            .unwrap()
            .size,
        None
    );
    assert!(selected(&rows, &HashSet::new()).is_empty());
}

#[test]
fn reclaim_subtracts_shared_image_layers_saturates_and_sorts_by_size() {
    let snapshot = disk(serde_json::json!({
        "Images": [
            {"Id":"small", "Containers":0, "Size":30, "SharedSize":10, "RepoTags":["small:1"]},
            {"Id":"large", "Containers":0, "Size":100, "SharedSize":20, "RepoTags":["large:1"]},
            {"Id":"overshared", "Containers":0, "Size":5, "SharedSize":99, "RepoTags":["overshared:1"]}
        ],
        "BuildCache": [
            {"ID":"cache-own", "Size":40, "InUse":false, "Shared":false},
            {"ID":"cache-shared", "Size":90, "InUse":false, "Shared":true}
        ]
    }));
    let rows = entries(&snapshot);
    let large = rows.iter().find(|row| row.id == "large").unwrap();
    assert_eq!(large.reclaim, Some(80));
    assert_eq!(
        rows.iter()
            .find(|row| row.id == "overshared")
            .unwrap()
            .reclaim,
        Some(0)
    );
    assert_eq!(
        rows.iter()
            .find(|row| row.id == "cache-shared")
            .unwrap()
            .reclaim,
        Some(0)
    );
    assert!(rows.windows(2).all(|pair| pair[0].size >= pair[1].size));
    assert_eq!(
        estimate(&[
            entry(Kind::Cache, "a", Some(u64::MAX)),
            entry(Kind::Image, "b", Some(9))
        ]),
        bytes(Some(u64::MAX))
    );
    assert_eq!(sum_sizes([Some(u64::MAX), Some(1)].into_iter()).0, u64::MAX);
}

#[test]
fn plan_preview_must_reach_each_item_before_two_confirmations() {
    let plan = vec![
        entry(Kind::Image, "image-id-full", Some(10)),
        entry(Kind::Container, "container-id-full", Some(20)),
    ];
    let mut flow = Flow::new(plan.clone()).unwrap();
    assert_eq!(flow.stage, Stage::Preview);
    assert!(
        flow.key(KeyCode::Char('y')).is_none(),
        "the second item has not been reviewed yet"
    );
    assert_eq!(flow.stage, Stage::Preview);
    assert!(flow.key(KeyCode::Down).is_none());
    assert_eq!(flow.cursor, 1);
    assert!(flow.body().contains("container-id-full"));
    assert!(flow.key(KeyCode::Char('y')).is_none());
    assert_eq!(flow.stage, Stage::Confirm);
    assert_eq!(flow.key(KeyCode::Char('y')), Some(plan));
}

#[test]
fn volume_plan_needs_second_confirmation_and_full_delete_phrase() {
    let plan = vec![entry(Kind::Volume, "named-volume", Some(512))];
    let mut flow = Flow::new(plan.clone()).unwrap();
    assert!(flow.body().contains("卷数据不可恢复"));
    assert!(flow.key(KeyCode::Char('y')).is_none());
    assert_eq!(flow.stage, Stage::Confirm);
    assert!(flow.key(KeyCode::Char('y')).is_none());
    assert_eq!(flow.stage, Stage::Volumes);
    assert_eq!(flow.volume_phrase(), "DELETE named-volume");
    for ch in "DELETE named-volumeX".chars() {
        assert!(flow.key(KeyCode::Char(ch)).is_none());
    }
    assert!(
        flow.key(KeyCode::Enter).is_none(),
        "incorrect full phrase does not authorize the plan"
    );
    assert!(flow.key(KeyCode::Backspace).is_none());
    assert_eq!(flow.key(KeyCode::Enter), Some(plan));
}

#[test]
fn every_volume_requires_its_own_full_name() {
    let plan = vec![
        entry(Kind::Volume, "first", Some(10)),
        entry(Kind::Volume, "second", Some(20)),
    ];
    let mut flow = Flow::new(plan.clone()).unwrap();
    flow.key(KeyCode::Down);
    flow.key(KeyCode::Char('y'));
    flow.key(KeyCode::Char('y'));
    for c in "DELETE first".chars() {
        flow.key(KeyCode::Char(c));
    }
    assert!(flow.key(KeyCode::Enter).is_none());
    assert_eq!(flow.volume_phrase(), "DELETE second");
    assert!(flow.input.is_empty());
    assert!(flow.key(KeyCode::Enter).is_none());
    for c in "DELETE second".chars() {
        flow.key(KeyCode::Char(c));
    }
    assert_eq!(flow.key(KeyCode::Enter), Some(plan));
}

#[test]
fn long_display_names_cannot_hide_full_preview_id() {
    let mut item = entry(Kind::Image, "sha256:review-this-exact-id", Some(1));
    item.name = "huge-tag".repeat(1000);
    let body = Flow::new(vec![item]).unwrap().body();
    assert!(body.find("sha256:review-this-exact-id").unwrap() < 100);
    assert!(body.len() < 1000);
}
