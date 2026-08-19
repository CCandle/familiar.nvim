use sha2::{Digest, Sha256};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

pub const DEFAULT_MODEL_ID: &str = "smollm2-135m-instruct-q4_k_m";
pub const DEFAULT_MODEL_FILE: &str = "SmolLM2-135M-Instruct-Q4_K_M.gguf";
pub const DEFAULT_MODEL_URL: &str = "https://huggingface.co/lmstudio-community/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf";
pub const DEFAULT_MODEL_SHA256: &str = "bda484992f9655d22504b14e57985257fa6a86937c61f957cf99c10a3bcae169";
pub const DEFAULT_MODEL_LICENSE: &str = "Apache-2.0";
pub const DEFAULT_MODEL_APPROX_BYTES: u64 = 105_000_000;

fn sha256(path: &Path) -> Result<String, String> {
    let mut file = File::open(path).map_err(|error| format!("open for checksum failed: {error}"))?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = file
            .read(&mut buffer)
            .map_err(|error| format!("checksum read failed: {error}"))?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn validate_gguf(path: &Path) -> Result<u64, String> {
    let metadata = fs::metadata(path).map_err(|error| format!("stat failed: {error}"))?;
    let size = metadata.len();
    if size < 80_000_000 || size > 140_000_000 {
        return Err(format!("unexpected model size: {size} bytes"));
    }

    let mut file = File::open(path).map_err(|error| format!("open failed: {error}"))?;
    let mut magic = [0_u8; 4];
    file.read_exact(&mut magic)
        .map_err(|error| format!("failed reading GGUF header: {error}"))?;
    if &magic != b"GGUF" {
        return Err("downloaded file is not a GGUF model".into());
    }

    let actual = sha256(path)?;
    if actual != DEFAULT_MODEL_SHA256 {
        return Err(format!(
            "model SHA-256 mismatch: expected {DEFAULT_MODEL_SHA256}, got {actual}"
        ));
    }
    Ok(size)
}

pub fn install(path: &Path, url: &str) -> Result<u64, String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| format!("create model directory failed: {error}"))?;
    }

    let tmp = PathBuf::from(format!("{}.part", path.display()));
    let _ = fs::remove_file(&tmp);

    let mut response = ureq::get(url)
        .call()
        .map_err(|error| format!("model download failed: {error}"))?;
    let mut reader = response.body_mut().as_reader();
    let mut file = File::create(&tmp).map_err(|error| format!("create temp model failed: {error}"))?;
    std::io::copy(&mut reader, &mut file).map_err(|error| format!("model download write failed: {error}"))?;
    file.flush().map_err(|error| format!("model flush failed: {error}"))?;
    drop(file);

    let size = match validate_gguf(&tmp) {
        Ok(size) => size,
        Err(error) => {
            let _ = fs::remove_file(&tmp);
            return Err(error);
        }
    };

    fs::rename(&tmp, path).map_err(|error| format!("install model failed: {error}"))?;
    Ok(size)
}

pub fn status(path: &Path) -> Result<Option<u64>, String> {
    if !path.exists() {
        return Ok(None);
    }
    validate_gguf(path).map(Some)
}

pub fn remove(path: &Path) -> Result<(), String> {
    if path.exists() {
        fs::remove_file(path).map_err(|error| format!("remove model failed: {error}"))?;
    }
    Ok(())
}

pub fn run_cli(args: &[String]) -> Result<bool, String> {
    if args.first().map(String::as_str) != Some("model") {
        return Ok(false);
    }

    let action = args.get(1).map(String::as_str).unwrap_or("status");
    let path = args
        .get(2)
        .map(PathBuf::from)
        .ok_or_else(|| "usage: familiar-core model <install|status|remove> <path> [url]".to_string())?;

    match action {
        "install" => {
            let url = args.get(3).map(String::as_str).unwrap_or(DEFAULT_MODEL_URL);
            let size = install(&path, url)?;
            println!(
                "{{\"ok\":true,\"action\":\"install\",\"model\":\"{}\",\"bytes\":{},\"sha256\":\"{}\",\"path\":{}}}",
                DEFAULT_MODEL_ID,
                size,
                DEFAULT_MODEL_SHA256,
                serde_json::to_string(&path.display().to_string()).unwrap_or_else(|_| "\"\"".into())
            );
        }
        "status" => {
            let size = status(&path)?;
            println!(
                "{{\"ok\":true,\"action\":\"status\",\"model\":\"{}\",\"installed\":{},\"bytes\":{},\"sha256\":\"{}\",\"path\":{}}}",
                DEFAULT_MODEL_ID,
                size.is_some(),
                size.unwrap_or(0),
                DEFAULT_MODEL_SHA256,
                serde_json::to_string(&path.display().to_string()).unwrap_or_else(|_| "\"\"".into())
            );
        }
        "remove" => {
            remove(&path)?;
            println!(
                "{{\"ok\":true,\"action\":\"remove\",\"model\":\"{}\",\"path\":{}}}",
                DEFAULT_MODEL_ID,
                serde_json::to_string(&path.display().to_string()).unwrap_or_else(|_| "\"\"".into())
            );
        }
        _ => return Err(format!("unknown model action: {action}")),
    }

    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_is_pinned_to_expected_small_model() {
        assert_eq!(DEFAULT_MODEL_ID, "smollm2-135m-instruct-q4_k_m");
        assert!(DEFAULT_MODEL_URL.contains("SmolLM2-135M-Instruct-Q4_K_M.gguf"));
        assert_eq!(DEFAULT_MODEL_SHA256.len(), 64);
        assert_eq!(DEFAULT_MODEL_LICENSE, "Apache-2.0");
        assert!(DEFAULT_MODEL_APPROX_BYTES < 120_000_000);
    }
}
