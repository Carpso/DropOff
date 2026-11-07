// Hugging Face free inference fallback (same pattern as churchonapp_flutter's kael-ai).
// Used when Cloudflare Workers AI is unavailable or throws.
const HF_API_BASE = 'https://api-inference.huggingface.co/models';
const HF_MODEL = 'mistralai/Mistral-7B-Instruct-v0.3';

export async function hfInfer(env: any, system: string, user: string): Promise<string | null> {
  const token = env?.HUGGINGFACE_TOKEN;
  if (!token) return null;
  const prompt = `<s>[INST] ${system}\n\n${user} [/INST]`;
  try {
    const res = await fetch(`${HF_API_BASE}/${HF_MODEL}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        inputs: prompt,
        parameters: { max_new_tokens: 300, temperature: 0.3, top_p: 0.9, do_sample: true, return_full_text: false },
        options: { wait_for_model: true },
      }),
    });
    if (!res.ok) return null;
    const data: any = await res.json().catch(() => null);
    if (Array.isArray(data) && data[0]?.generated_text) return String(data[0].generated_text).trim();
    if (typeof data?.generated_text === 'string') return data.generated_text.trim();
    if (typeof data?.[0] === 'string') return data[0].trim();
    return null;
  } catch {
    return null;
  }
}
