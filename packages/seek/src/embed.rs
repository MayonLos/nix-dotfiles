use crate::config;
use anyhow::{Context, Result};
use fastembed::{
    InitOptionsUserDefined, Pooling, QuantizationMode, TextEmbedding, TokenizerFiles,
    UserDefinedEmbeddingModel,
};
use std::{fs, path::Path, time::Duration};
pub const REVISION: &str = "75c43b069aac4d136ba6bc1122f995fedcfd2781";
const FILES: &[&str] = &[
    "config.json",
    "tokenizer.json",
    "special_tokens_map.json",
    "tokenizer_config.json",
    "onnx/model_quantized.onnx",
];
pub fn download(data: &Path) -> Result<()> {
    let root = data.join("model").join(REVISION);
    config::private_dir(&root)?;
    println!(
        "仅下载公开 BGE-small-zh-v1.5 INT8 模型（约 25 MB），不发送本地资料。revision={REVISION}"
    );
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(300))
        .build()?;
    for f in FILES {
        let path = root.join(f);
        if path.is_file() {
            continue;
        }
        let bytes = client
            .get(format!(
                "https://huggingface.co/Xenova/bge-small-zh-v1.5/resolve/{REVISION}/{f}"
            ))
            .send()?
            .error_for_status()?
            .bytes()?;
        config::atomic(&path, &bytes)?;
    }
    println!("模型已保存：{}", root.display());
    Ok(())
}
pub fn load(data: &Path) -> Result<TextEmbedding> {
    let root = data.join("model").join(REVISION);
    let read = |f: &str| {
        fs::read(root.join(f)).context("模型未就绪；运行 seek model download（仅下载公开模型），或配置 embeddings=false 使用纯 BM25")
    };
    let tokenizer = TokenizerFiles {
        tokenizer_file: read("tokenizer.json")?,
        config_file: read("config.json")?,
        special_tokens_map_file: read("special_tokens_map.json")?,
        tokenizer_config_file: read("tokenizer_config.json")?,
    };
    TextEmbedding::try_new_from_user_defined(
        UserDefinedEmbeddingModel::new(read("onnx/model_quantized.onnx")?, tokenizer)
            .with_pooling(Pooling::Cls)
            .with_quantization(QuantizationMode::Dynamic),
        InitOptionsUserDefined::new().with_max_length(512),
    )
    .context("无法加载本地 CPU 嵌入模型；检查 ORT_DYLIB_PATH 与 ONNX Runtime 版本")
}
pub fn vector(model: &mut TextEmbedding, text: &str, query: bool) -> Result<Vec<f32>> {
    let text = if query {
        format!("为这个句子生成表示以用于检索相关文章：{text}")
    } else {
        text.to_owned()
    };
    let mut v = model.embed(vec![text], Some(1))?;
    Ok(normalize(v.remove(0)))
}
/// Unit normalization is done once when loading the corpus and per query.
pub fn normalize(mut v: Vec<f32>) -> Vec<f32> {
    let norm = v.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > 0.0 {
        for x in &mut v {
            *x /= norm;
        }
    }
    v
}
pub fn dot(a: &[f32], b: &[f32]) -> f32 {
    if a.len() != b.len() {
        return 0.0;
    }
    a.iter().zip(b).map(|(x, y)| x * y).sum()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unit_vectors_have_cosine_dot() {
        let a = normalize(vec![3.0, 4.0]);
        assert!((dot(&a, &a) - 1.0).abs() < 1e-6);
        assert_eq!(dot(&normalize(vec![0.0, 0.0]), &a), 0.0);
    }
}
