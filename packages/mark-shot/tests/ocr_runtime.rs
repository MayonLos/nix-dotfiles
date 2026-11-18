#![cfg(all(target_os = "linux", feature = "ocr-dynamic"))]

use mark_shot::ocr::{
    self,
    models::{ModelFiles, ModelStatus},
    runtime_library,
};
use std::{
    path::PathBuf,
    process::Command,
    time::{Duration, Instant},
};

/// 【识别运行库】【隔离进程】以 name 重新执行当前测试，设置独立数据目录；返回是否已在子进程
fn isolated(name: &str, ignored: bool) -> bool {
    if std::env::var("MARK_SHOT_RUNTIME_CHILD").as_deref() == Ok(name) {
        return true;
    }
    let root = tempfile::tempdir().unwrap();
    let mut command = Command::new(std::env::current_exe().unwrap());
    command.args(["--exact", name, "--nocapture"]);
    if ignored {
        command.arg("--ignored");
    }
    let output = command
        .env("MARK_SHOT_RUNTIME_CHILD", name)
        .env("XDG_DATA_HOME", root.path().join("data"))
        .env("XDG_STATE_HOME", root.path().join("state"))
        .env("XDG_CONFIG_HOME", root.path().join("config"))
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    print!("{}", String::from_utf8_lossy(&output.stdout));
    false
}

/// 【识别运行库】【首次运行回归】无参数，验证普通初始化与加载失败不创建运行库文件或安装任务
#[test]
fn first_use_never_starts_a_download() {
    if !isolated("first_use_never_starts_a_download", false) {
        return;
    }
    let models = ocr::models::OcrModels::load();
    assert!(!models.needs_poll());
    assert_eq!(models.library.status, ModelStatus::Missing);
    assert!(ocr::engine_choice::source(&models).is_none());
    assert!(
        runtime_library::load()
            .unwrap_err()
            .contains("Install or repair")
    );
    assert!(!runtime_library::directory().unwrap().exists());
}

/// 【识别运行库】【实际识别回归】使用环境变量指定的官方归档和模型，显式安装后识别固定图片；不下载测试资源
#[test]
#[ignore = "requires MARK_SHOT_TEST_ORT_ARCHIVE and MARK_SHOT_TEST_OCR_MODELS"]
fn explicit_install_runs_real_ocr_offline() {
    if !isolated("explicit_install_runs_real_ocr_offline", true) {
        return;
    }
    let archive =
        PathBuf::from(std::env::var_os("MARK_SHOT_TEST_ORT_ARCHIVE").expect("official archive"));
    let models =
        PathBuf::from(std::env::var_os("MARK_SHOT_TEST_OCR_MODELS").expect("verified OCR models"));
    let root = runtime_library::directory().unwrap();
    std::fs::create_dir_all(&root).unwrap();
    std::fs::copy(
        archive,
        root.join(runtime_library::manifest::current().unwrap().archive.file),
    )
    .unwrap();
    let mut installer = runtime_library::Installer::default();
    assert_eq!(installer.status, ModelStatus::Missing);
    assert!(!installer.needs_poll());
    installer.start();
    let deadline = Instant::now() + Duration::from_secs(30);
    while installer.needs_poll() {
        installer.poll();
        assert!(Instant::now() < deadline, "installation timed out");
        std::thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(
        installer.status,
        ModelStatus::Installed,
        "{:?}",
        installer.error
    );
    let files = ModelFiles {
        detector: models.join("pp-ocrv5_mobile_det.onnx"),
        recognizer: models.join("pp-ocrv5_mobile_rec.onnx"),
        dict: models.join("ppocrv5_dict.txt"),
    };
    let backend = ocr::default_backend(&files).unwrap();
    let image = image::open(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/ocr.png"
    ))
    .unwrap()
    .to_rgb8();
    let output = backend
        .recognize(
            ocr::OcrImage {
                width: image.width(),
                height: image.height(),
                rgb: image.into_raw(),
                origin: (0.0, 0.0),
            },
            &|| false,
        )
        .unwrap();
    assert_eq!(
        output
            .lines
            .iter()
            .map(|line| line.text.as_str())
            .collect::<Vec<_>>(),
        [
            "Wayland Native Screenshot",
            "Mark Shot OCR 2026",
            "Local text recognition"
        ]
    );
    println!(
        "Recognized {} lines: {:?}",
        output.lines.len(),
        output
            .lines
            .iter()
            .map(|line| &line.text)
            .collect::<Vec<_>>()
    );
}

const REAL_OCR_CHILD: &str = "MARK_SHOT_REAL_OCR_CHILD";

/// Run this test binary again as an `installed_runtime_runs_real_ocr` child
/// with private XDG directories. The positive child keeps the ambient
/// `LD_LIBRARY_PATH` that the packaged wrapper fills with `ortRuntime`; the
/// negative child drops it to reproduce the NixOS failure.
fn real_ocr_child(
    mode: &str,
    root: &std::path::Path,
    models: &std::path::Path,
) -> std::process::Output {
    let mut command = Command::new(std::env::current_exe().unwrap());
    command
        .args([
            "--exact",
            "installed_runtime_runs_real_ocr",
            "--ignored",
            "--nocapture",
        ])
        .env(REAL_OCR_CHILD, mode)
        .env("MARK_SHOT_TEST_OCR_MODELS", models)
        .env("XDG_DATA_HOME", root.join("data"))
        .env("XDG_STATE_HOME", root.join("state"))
        .env("XDG_CONFIG_HOME", root.join("config"));
    if mode == "negative" {
        command.env_remove("LD_LIBRARY_PATH");
    }
    command.output().unwrap()
}

/// The installed ONNX Runtime directory, overridable for other machines.
fn installed_runtime_dir() -> PathBuf {
    std::env::var_os("MARK_SHOT_TEST_ORT_INSTALL_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| runtime_library::directory().unwrap().join("installed"))
}

/// The verified OCR model directory, overridable for other machines.
fn models_dir() -> PathBuf {
    std::env::var_os("MARK_SHOT_TEST_OCR_MODELS")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            runtime_library::directory()
                .unwrap()
                .parent()
                .unwrap()
                .parent()
                .unwrap()
                .join("models")
        })
}

/// 【识别运行库】【真实识别回归】用已安装运行库识别固定图片；需要 wrapper 的 LD_LIBRARY_PATH 含 C++ 运行库，不访问网络
#[test]
#[ignore = "requires an installed ONNX Runtime, OCR models and the wrapper's LD_LIBRARY_PATH"]
fn installed_runtime_runs_real_ocr() {
    if let Ok(mode) = std::env::var(REAL_OCR_CHILD) {
        match mode.as_str() {
            "positive" => recognize_with_installed_runtime(),
            "negative" => assert_missing_cxx_runtime_is_reported(),
            other => panic!("unknown child mode {other}"),
        }
        return;
    }

    let root = tempfile::tempdir().unwrap();
    let installed = installed_runtime_dir();
    let models = models_dir();
    let distribution = runtime_library::manifest::current().expect("supported runtime platform");
    for asset in [&distribution.library, &distribution.shared] {
        assert!(
            installed.join(asset.file).is_file(),
            "{} is missing; install the OCR runtime from the panel or set MARK_SHOT_TEST_ORT_INSTALL_DIR",
            installed.join(asset.file).display()
        );
    }
    for name in [
        "pp-ocrv5_mobile_det.onnx",
        "pp-ocrv5_mobile_rec.onnx",
        "ppocrv5_dict.txt",
    ] {
        assert!(
            models.join(name).is_file(),
            "{} is missing; install the OCR models or set MARK_SHOT_TEST_OCR_MODELS",
            models.join(name).display()
        );
    }

    // Copy the verified runtime into the child's private data directory so a
    // run never writes to the user's own runtime installation.
    let target = root
        .path()
        .join("data/mark-shot/runtime")
        .join(runtime_library::directory().unwrap().file_name().unwrap())
        .join("installed");
    std::fs::create_dir_all(&target).unwrap();
    for entry in std::fs::read_dir(&installed).unwrap() {
        let entry = entry.unwrap();
        std::fs::copy(entry.path(), target.join(entry.file_name())).unwrap();
    }

    let positive = real_ocr_child("positive", root.path(), &models);
    print!("{}", String::from_utf8_lossy(&positive.stdout));
    assert!(
        positive.status.success(),
        "the wrapped-binary environment must load the runtime and recognize text:\n{}",
        String::from_utf8_lossy(&positive.stderr)
    );

    let negative = real_ocr_child("negative", root.path(), &models);
    print!("{}", String::from_utf8_lossy(&negative.stdout));
    assert!(
        negative.status.success(),
        "without the C++ runtime on LD_LIBRARY_PATH the error must name it:\n{}",
        String::from_utf8_lossy(&negative.stderr)
    );
}

/// Build the real engine and recognize the fixture. Each case runs in its own
/// child process because ONNX Runtime initializes once per process.
fn recognize_with_installed_runtime() {
    let models = PathBuf::from(std::env::var_os("MARK_SHOT_TEST_OCR_MODELS").unwrap());
    let files = ModelFiles {
        detector: models.join("pp-ocrv5_mobile_det.onnx"),
        recognizer: models.join("pp-ocrv5_mobile_rec.onnx"),
        dict: models.join("ppocrv5_dict.txt"),
    };
    let backend = ocr::default_backend(&files).expect(
        "the installed runtime must load; run with default.nix's ortRuntime on LD_LIBRARY_PATH",
    );
    let image = image::open(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/ocr.png"
    ))
    .unwrap()
    .to_rgb8();
    let output = backend
        .recognize(
            ocr::OcrImage {
                width: image.width(),
                height: image.height(),
                rgb: image.into_raw(),
                origin: (0.0, 0.0),
            },
            &|| false,
        )
        .unwrap();
    let lines: Vec<_> = output.lines.iter().map(|line| line.text.as_str()).collect();
    println!("recognized {} lines: {lines:?}", lines.len());
    assert_eq!(
        lines,
        [
            "Wayland Native Screenshot",
            "Mark Shot OCR 2026",
            "Local text recognition"
        ]
    );
}

/// Without the C++ runtime on `LD_LIBRARY_PATH` a distro that has no global
/// `/usr/lib` must report the missing library instead of only "dlopen failed".
fn assert_missing_cxx_runtime_is_reported() {
    match runtime_library::load() {
        Ok(()) => {
            println!("no negative control: a system C++ runtime is reachable from the test binary")
        }
        Err(error) => {
            println!("{error}");
            assert!(error.contains("Install or repair"), "{error}");
            assert!(
                error.contains("failed to load from"),
                "the runtime path was dropped from: {error}"
            );
            assert!(
                error.contains("libstdc++.so.6") || error.contains("libgcc_s.so.1"),
                "the dynamic loader detail is missing from: {error}"
            );
        }
    }
}
