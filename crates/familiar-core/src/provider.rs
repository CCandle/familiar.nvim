use crate::protocol::{BrainConfig, EditorSnapshot};
use serde_json::{Value, json};
use std::time::Duration;

const SYSTEM_PROMPT: &str = "You are the low-frequency behavior director for a tiny nonverbal Neovim familiar. Choose one behavior only. Never speak to the user. Prefer continuity and calm over novelty.";

pub struct PolicyRequest<'a> {
    pub snapshot: &'a EditorSnapshot,
    pub allowed: &'a [&'static str],
    pub previous: &'a str,
}

pub fn build_prompt(request: PolicyRequest<'_>) -> String {
    let snapshot = request.snapshot;
    let mut context = String::new();
    for line in &snapshot.context.before {
        context.push_str("  ");
        context.push_str(line);
        context.push('\n');
    }
    if !snapshot.context.current_line.is_empty() {
        context.push_str("> ");
        context.push_str(&snapshot.context.current_line);
        context.push('\n');
    }
    for line in &snapshot.context.after {
        context.push_str("  ");
        context.push_str(line);
        context.push('\n');
    }

    format!(
        "Reply with exactly ONE word from this list: {}\n\
mode={} filetype={} modified={} errors={} warnings={} idle_ms={} buffer_switches_10s={} previous={}\n\
Nearby editor text:\n{}\
Pick the behavior that feels natural and useful. Do not explain.",
        request.allowed.join(" | "),
        snapshot.mode,
        snapshot.buffer.filetype,
        snapshot.buffer.modified,
        snapshot.diagnostics.errors,
        snapshot.diagnostics.warnings,
        snapshot.activity.idle_ms,
        snapshot.activity.buffer_switches_10s,
        request.previous,
        context,
    )
}

pub enum ProviderEngine {
    OpenAi(OpenAiCompatibleProvider),
    #[cfg(feature = "local-llama")]
    Local(LocalLlamaProvider),
}

impl ProviderEngine {
    pub fn from_config(config: &BrainConfig) -> Result<Self, String> {
        match config.provider.as_str() {
            "ollama" | "openai_compatible" => {
                Ok(Self::OpenAi(OpenAiCompatibleProvider::new(config)?))
            }
            "local_llama" => {
                #[cfg(feature = "local-llama")]
                {
                    Ok(Self::Local(LocalLlamaProvider::new(config)?))
                }
                #[cfg(not(feature = "local-llama"))]
                {
                    Err("local_llama provider requires building familiar-core with --features local-llama".into())
                }
            }
            other => Err(format!("unsupported AI provider: {other}")),
        }
    }

    pub fn query(&mut self, prompt: &str) -> Result<String, String> {
        match self {
            Self::OpenAi(provider) => provider.query(prompt),
            #[cfg(feature = "local-llama")]
            Self::Local(provider) => provider.query(prompt),
        }
    }
}

pub struct OpenAiCompatibleProvider {
    agent: ureq::Agent,
    endpoint: String,
    model: String,
    api_key: Option<String>,
    temperature: f32,
    max_tokens: u32,
}

impl OpenAiCompatibleProvider {
    pub fn new(config: &BrainConfig) -> Result<Self, String> {
        let endpoint = match (config.provider.as_str(), config.endpoint.as_deref()) {
            ("ollama", None) => "http://127.0.0.1:11434/v1/chat/completions".to_string(),
            (_, Some(endpoint)) if !endpoint.trim().is_empty() => endpoint.to_string(),
            _ => return Err("brain.endpoint is required for openai_compatible".into()),
        };
        let model = config
            .model
            .clone()
            .filter(|model| !model.trim().is_empty())
            .ok_or_else(|| "brain.model is required for ollama/openai_compatible".to_string())?;

        let agent_config = ureq::Agent::config_builder()
            .timeout_global(Some(Duration::from_millis(config.timeout_ms.max(250))))
            .build();
        let agent: ureq::Agent = agent_config.into();

        Ok(Self {
            agent,
            endpoint,
            model,
            api_key: config.api_key.clone().filter(|key| !key.is_empty()),
            temperature: config.temperature,
            max_tokens: config.max_tokens,
        })
    }

    pub fn query(&mut self, prompt: &str) -> Result<String, String> {
        let body = json!({
            "model": self.model,
            "messages": [
                { "role": "system", "content": SYSTEM_PROMPT },
                { "role": "user", "content": prompt }
            ],
            "temperature": self.temperature,
            "max_tokens": self.max_tokens,
            "stream": false
        });

        let mut request = self.agent.post(&self.endpoint);
        if let Some(key) = &self.api_key {
            request = request.header("Authorization", format!("Bearer {key}"));
        }

        let mut response = request
            .send_json(&body)
            .map_err(|error| format!("provider request failed: {error}"))?;
        let value: Value = response
            .body_mut()
            .read_json()
            .map_err(|error| format!("provider response was not JSON: {error}"))?;

        value
            .pointer("/choices/0/message/content")
            .and_then(Value::as_str)
            .map(str::to_string)
            .ok_or_else(|| "provider response missing choices[0].message.content".into())
    }
}

#[cfg(feature = "local-llama")]
pub struct LocalLlamaProvider {
    backend: llama_cpp_4::prelude::LlamaBackend,
    model: llama_cpp_4::prelude::LlamaModel,
    n_ctx: u32,
    n_threads: i32,
    temperature: f32,
    max_tokens: u32,
}

#[cfg(feature = "local-llama")]
impl LocalLlamaProvider {
    pub fn new(config: &BrainConfig) -> Result<Self, String> {
        use llama_cpp_4::prelude::*;
        use std::pin::pin;

        let model_path = config
            .local_config
            .model_path
            .as_deref()
            .filter(|path| !path.is_empty())
            .ok_or_else(|| "brain.local.model_path is required for local_llama".to_string())?;
        let backend =
            LlamaBackend::init().map_err(|error| format!("llama backend init failed: {error}"))?;
        let mut params =
            LlamaModelParams::default().with_n_gpu_layers(config.local_config.n_gpu_layers);
        let params = pin!(params);
        let model = LlamaModel::load_from_file(&backend, model_path, &params)
            .map_err(|error| format!("failed to load local model {model_path}: {error}"))?;

        Ok(Self {
            backend,
            model,
            n_ctx: config.local_config.n_ctx.max(512),
            n_threads: config.local_config.n_threads.max(1),
            temperature: config.temperature,
            max_tokens: config.max_tokens.max(1),
        })
    }

    pub fn query(&mut self, prompt: &str) -> Result<String, String> {
        use llama_cpp_4::prelude::*;
        use std::num::NonZeroU32;

        let messages = vec![
            LlamaChatMessage::new("system".into(), SYSTEM_PROMPT.into())
                .map_err(|error| format!("chat message failed: {error}"))?,
            LlamaChatMessage::new("user".into(), prompt.into())
                .map_err(|error| format!("chat message failed: {error}"))?,
        ];
        let rendered = self
            .model
            .apply_chat_template(None, messages, true)
            .map_err(|error| format!("chat template failed: {error}"))?;
        let tokens = self
            .model
            .str_to_token(&rendered, AddBos::Never)
            .map_err(|error| format!("tokenization failed: {error}"))?;
        if tokens.len() >= self.n_ctx as usize {
            return Err(format!(
                "local prompt is too large: {} tokens for n_ctx={}",
                tokens.len(),
                self.n_ctx
            ));
        }

        let params = LlamaContextParams::default()
            .with_n_ctx(NonZeroU32::new(self.n_ctx))
            .with_n_batch(self.n_ctx.min(512))
            .with_n_threads(self.n_threads);
        let mut ctx = self
            .model
            .new_context(&self.backend, params)
            .map_err(|error| format!("local context failed: {error}"))?;
        let mut batch = LlamaBatch::new(self.n_ctx as usize, 1);
        for (index, token) in tokens.iter().copied().enumerate() {
            batch
                .add(token, index as i32, &[0], index == tokens.len() - 1)
                .map_err(|error| format!("local batch failed: {error}"))?;
        }
        ctx.decode(&mut batch)
            .map_err(|error| format!("local prompt decode failed: {error}"))?;

        let sampler = if self.temperature <= 0.0 {
            LlamaSampler::chain_simple([LlamaSampler::greedy()])
        } else {
            LlamaSampler::chain_simple([
                LlamaSampler::top_k(20),
                LlamaSampler::top_p(0.9, 1),
                LlamaSampler::temp(self.temperature),
                LlamaSampler::dist(0),
            ])
        };

        let mut output = String::new();
        let mut pos = tokens.len() as i32;
        let mut logits_index = batch.n_tokens() - 1;
        for _ in 0..self.max_tokens {
            let token = sampler.sample(&ctx, logits_index);
            if self.model.is_eog_token(token) {
                break;
            }
            let bytes = self
                .model
                .token_to_bytes(token, Special::Plaintext)
                .map_err(|error| format!("local token decode failed: {error}"))?;
            output.push_str(&String::from_utf8_lossy(&bytes));

            batch.clear();
            batch
                .add(token, pos, &[0], true)
                .map_err(|error| format!("local batch failed: {error}"))?;
            ctx.decode(&mut batch)
                .map_err(|error| format!("local decode failed: {error}"))?;
            logits_index = 0;
            pos += 1;
        }

        Ok(output)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{
        ActivitySnapshot, BufferSnapshot, DiagnosticSnapshot, TextContextSnapshot, ViewportSnapshot,
    };

    #[test]
    fn prompt_is_small_and_action_bounded() {
        let snapshot = EditorSnapshot {
            mode: "n".into(),
            buffer: BufferSnapshot {
                id: 1,
                name: "main.rs".into(),
                filetype: "rust".into(),
                modified: true,
                line_count: 20,
            },
            viewport: ViewportSnapshot {
                width: 120,
                height: 40,
                cursor_row: 10,
                cursor_col: 2,
                topline: 1,
                botline: 20,
                line_display_widths: vec![],
            },
            diagnostics: DiagnosticSnapshot {
                errors: 1,
                warnings: 0,
            },
            activity: ActivitySnapshot {
                idle_ms: 100,
                typing: false,
                buffer_switches_10s: 0,
            },
            context: TextContextSnapshot {
                current_line: "let answer = 42;".into(),
                before: vec!["fn main() {".into()],
                after: vec!["}".into()],
            },
        };
        let prompt = build_prompt(PolicyRequest {
            snapshot: &snapshot,
            allowed: &["focus", "inspect"],
            previous: "idle",
        });
        assert!(prompt.contains("focus | inspect"));
        assert!(prompt.contains("let answer = 42"));
        assert!(prompt.len() < 2_000);
    }
}
