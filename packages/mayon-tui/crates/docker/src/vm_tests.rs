use super::*;
use std::{
    fs::{self, File},
    os::unix::fs::MetadataExt,
    sync::atomic::{AtomicU64, Ordering},
};

static NEXT_DIR: AtomicU64 = AtomicU64::new(0);

struct Fixture(PathBuf);

impl Fixture {
    fn new() -> Self {
        let id = NEXT_DIR.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!("mayon-vm-tests-{}-{id}", std::process::id()));
        fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    fn file(&self, name: &str, size: u64) -> PathBuf {
        let path = self.0.join(name);
        File::create(&path).unwrap().set_len(size).unwrap();
        path
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn row(uri: &str, kind: &str, path: Option<PathBuf>, actual: Option<u64>) -> Row {
    Row {
        uri: uri.into(),
        owner: "fixture".into(),
        kind: kind.into(),
        path,
        actual,
        virtual_size: None,
        note: String::new(),
        identity: None,
    }
}

fn connection(uri: &str, complete: bool) -> Connection {
    Connection {
        uri: uri.into(),
        status: "fixture".into(),
        complete,
    }
}

#[test]
fn metadata_row_reports_sparse_file_allocation_separately_from_virtual_size() {
    let fixture = Fixture::new();
    let logical = 64 * 1024 * 1024;
    let path = fixture.file("sparse disk.qcow2", logical);
    let metadata = fs::metadata(&path).unwrap();
    let disk = metadata_row(
        "qemu:///session",
        "guest",
        "磁盘",
        Some(path),
        Some(logical),
        "fixture",
    );

    assert_eq!(disk.actual, Some(metadata.blocks().saturating_mul(512)));
    assert_eq!(disk.virtual_size, Some(logical));
    assert_ne!(disk.actual, disk.virtual_size);
}

#[test]
fn volume_paths_preserves_spaces_and_rejects_unknown_block_path_rows() {
    let rows = volume_paths(
        "Name                 Path\n----------------------------------------\nbase disk.qcow2       /pool with spaces/基础镜像.qcow2\n",
    )
    .unwrap();
    assert_eq!(rows, ["/pool with spaces/基础镜像.qcow2"]);
    assert!(volume_paths("Name Path\n----------------\nvolume0 unknownblockpath\n").is_err());
}

#[test]
fn merge_protects_cross_connection_base_refs_and_hardlinks_and_deduplicates_summary() {
    let fixture = Fixture::new();
    let base = fixture.file("base.qcow2", 32 * 1024 * 1024);
    let hardlink = fixture.0.join("orphan-looking.qcow2");
    fs::hard_link(&base, &hardlink).unwrap();
    let base = canonical(&base);
    let hardlink = canonical(&hardlink);

    let mut session = Census::default();
    session.refs.insert(base.clone());
    session.rows.push(metadata_row(
        "qemu:///session",
        "guest",
        "依赖",
        Some(base.clone()),
        None,
        "backingStore",
    ));
    let mut system = Census::default();
    system.volumes.push(metadata_row(
        "qemu:///system",
        "pool",
        "扫描文件",
        Some(base.clone()),
        None,
        "pool file",
    ));
    system.volumes.push(metadata_row(
        "qemu:///system",
        "pool",
        "扫描文件",
        Some(hardlink.clone()),
        None,
        "hardlink alias",
    ));

    let expected_actual = fs::metadata(&base).unwrap().blocks().saturating_mul(512);
    let inventory = merge(vec![
        (session, connection("qemu:///session", true)),
        (system, connection("qemu:///system", true)),
    ]);
    for path in [&base, &hardlink] {
        let volume = inventory
            .rows
            .iter()
            .find(|candidate| {
                candidate.uri == "qemu:///system" && candidate.path.as_ref() == Some(path)
            })
            .unwrap();
        assert_eq!(volume.kind, "依赖");
    }
    let summary = inventory.summary();
    assert!(summary.contains(&cleanup::bytes(Some(expected_actual))));
    let expected_virtual = cleanup::bytes(Some(0));
    assert!(summary.contains(&expected_virtual));
}

#[test]
fn incomplete_connections_turn_unreferenced_images_into_pending_review() {
    let fixture = Fixture::new();
    let image = canonical(&fixture.file("candidate.qcow2", 4096));
    let mut census = Census::default();
    census.volumes.push(metadata_row(
        "qemu:///session",
        "pool",
        "扫描文件",
        Some(image.clone()),
        None,
        "candidate",
    ));

    let inventory = merge(vec![(census, connection("qemu:///session", false))]);
    let candidate = inventory
        .rows
        .iter()
        .find(|candidate| candidate.path.as_ref() == Some(&image))
        .unwrap();
    assert_eq!(candidate.kind, "未引用待核实");
}

#[test]
fn snapshot_file_references_protect_volume_candidates() {
    let fixture = Fixture::new();
    let snapshot_disk = canonical(&fixture.file("snapshot.qcow2", 8192));
    let mut census = Census::default();
    census.refs.insert(snapshot_disk.clone());
    census.rows.push(metadata_row(
        "qemu:///system",
        "guest / snapshot",
        "快照磁盘",
        Some(snapshot_disk.clone()),
        None,
        "snapshot reference",
    ));
    census.volumes.push(metadata_row(
        "qemu:///system",
        "pool",
        "扫描文件",
        Some(snapshot_disk.clone()),
        None,
        "pool alias",
    ));

    let inventory = merge(vec![(census, connection("qemu:///system", true))]);
    let disk = inventory
        .rows
        .iter()
        .find(|candidate| {
            candidate.uri == "qemu:///system" && candidate.path.as_ref() == Some(&snapshot_disk)
        })
        .unwrap();
    assert_eq!(disk.kind, "快照磁盘");
    assert!(disk.note.contains("snapshot reference"));
}

#[test]
fn merge_sorts_known_actual_sizes_descending_then_unknown_and_keeps_missing_paths() {
    let census = Census {
        volumes: vec![
            row("qemu:///session", "小", Some("/z".into()), Some(10)),
            row("qemu:///session", "大", Some("/a".into()), Some(20)),
        ],
        rows: vec![row("qemu:///session", "未知", None, None)],
        ..Census::default()
    };
    let inventory = merge(vec![(census, connection("qemu:///session", true))]);
    assert_eq!(inventory.rows[0].actual, Some(20));
    assert_eq!(inventory.rows[0].path.as_deref(), Some(Path::new("/a")));
    assert_eq!(inventory.rows[1].actual, Some(10));
    assert_eq!(inventory.rows[1].path.as_deref(), Some(Path::new("/z")));
    assert_eq!(inventory.rows[2].actual, None);
    assert!(inventory.rows[2].path.is_none());
}

#[test]
fn vm_rows_are_separate_from_docker_cleanup_selection_types() {
    let vm = row(
        "qemu:///system",
        "镜像",
        Some("/vm/disk.qcow2".into()),
        Some(10),
    );
    let docker_rows = vec![cleanup::Entry {
        kind: cleanup::Kind::Cache,
        id: "cache-id".into(),
        name: "Docker cache".into(),
        size: Some(20),
        reclaim: Some(20),
        blocked: None,
    }];
    let keys = HashSet::from([vm.key(), docker_rows[0].key()]);

    // The only input accepted by Docker's destructive selector is cleanup::Entry;
    // VM rows cannot enter this channel and there is no VM cleanup conversion.
    let selected: Vec<cleanup::Entry> = cleanup::selected(&docker_rows, &keys);
    assert_eq!(selected, docker_rows);
}

fn missing_path(name: &str) -> PathBuf {
    std::env::temp_dir()
        .join(format!("mayon-vm-domain-disks-{}", std::process::id()))
        .join(name)
}

#[tokio::test]
async fn domain_disks_collects_backing_datastore_and_mirror_references() {
    let top = missing_path("top.qcow2");
    let base = missing_path("base.qcow2");
    let data = missing_path("data.qcow2");
    let mirror_source = missing_path("mirror-source.qcow2");
    let legacy_mirror = missing_path("legacy-mirror.qcow2");
    let xml = format!(
        r#"<domain><devices><disk type="file" device="disk">
          <driver type="qcow2"/><source file="{}"/>
          <backingStore type="file"><format type="qcow2"/><source file="{}"/><backingStore/></backingStore>
          <dataStore><source file="{}"/></dataStore>
          <mirror file="{}"><source file="{}"/></mirror>
        </disk></devices></domain>"#,
        top.display(),
        base.display(),
        data.display(),
        legacy_mirror.display(),
        mirror_source.display(),
    );
    let root = vm_xml::parse(&xml).unwrap();
    let mut census = Census::default();

    domain_disks(&mut census, "qemu:///session", "fixture", &root, false).await;

    for path in [top, base, data, mirror_source, legacy_mirror] {
        assert!(census.refs.contains(&path), "missing reference {path:?}");
    }
    assert!(
        census.warnings.is_empty(),
        "unexpected warnings: {:?}",
        census.warnings
    );
}

#[tokio::test]
async fn domain_disks_marks_unterminated_backing_chain_incomplete() {
    let top = missing_path("unterminated-top.qcow2");
    let base = missing_path("unterminated-base.qcow2");
    let xml = format!(
        r#"<domain><devices><disk type="file" device="disk">
          <driver type="qcow2"/><source file="{}"/>
          <backingStore type="file"><source file="{}"/></backingStore>
        </disk></devices></domain>"#,
        top.display(),
        base.display(),
    );
    let root = vm_xml::parse(&xml).unwrap();
    let mut census = Census::default();

    domain_disks(&mut census, "qemu:///system", "fixture", &root, false).await;

    assert!(census.refs.contains(&top));
    assert!(census.refs.contains(&base));
    assert!(census
        .warnings
        .iter()
        .any(|warning| warning.contains("backing 链未明确终止")));
}

#[tokio::test]
async fn raw_disk_without_backing_chain_is_complete() {
    let raw = missing_path("raw-without-chain.img");
    let xml = format!(
        r#"<domain><devices><disk type="file" device="disk">
          <driver type="raw"/><source file="{}"/>
        </disk></devices></domain>"#,
        raw.display(),
    );
    let root = vm_xml::parse(&xml).unwrap();
    let mut census = Census::default();

    domain_disks(&mut census, "qemu:///session", "fixture", &root, false).await;

    assert!(census.refs.contains(&raw));
    assert!(
        census.warnings.is_empty(),
        "unexpected warnings: {:?}",
        census.warnings
    );
}

#[test]
fn cross_connection_iso_aliases_stay_iso_and_do_not_inflate_virtual_disk_capacity() {
    let fixture = Fixture::new();
    let path = fixture.file("installer.iso", 1024);
    let mut session = Census::default();
    session.refs.insert(canonical(&path));
    session.rows.push(metadata_row(
        URIS[0],
        "vm",
        "ISO",
        Some(canonical(&path)),
        Some(1024),
        "mounted",
    ));
    let mut system = Census::default();
    system.volumes.push(metadata_row(
        URIS[1],
        "pool",
        "扫描文件",
        Some(canonical(&path)),
        Some(1024),
        "file",
    ));
    let report = merge(vec![
        (session, connection(URIS[0], true)),
        (system, connection(URIS[1], true)),
    ]);
    assert!(report
        .rows
        .iter()
        .filter(|r| r.path.is_some())
        .all(|r| r.kind == "ISO"));
    assert!(report.summary().contains("已知虚拟 0.0 B"));
}
