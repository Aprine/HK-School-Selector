import express from 'express';
import cors from 'cors';

const app = express();
const port = process.env.PORT || 8080;

const DASHSCOPE_API_KEY = process.env.DASHSCOPE_API_KEY || '';
const QWEN_MODEL = process.env.QWEN_MODEL || 'qwen-turbo';
const QWEN_ENDPOINT =
  process.env.QWEN_ENDPOINT ||
  'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';

app.use(cors());
app.use(express.json({ limit: '256kb' }));

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    model: QWEN_MODEL,
    keyConfigured: DASHSCOPE_API_KEY.length > 0,
  });
});

app.post('/ai/chat', async (req, res) => {
  try {
    if (!DASHSCOPE_API_KEY) {
      return res.status(500).json({ error: 'DASHSCOPE_API_KEY is missing.' });
    }

    const { history = [], userMessage = '', appContext = '' } = req.body || {};
    const text = String(userMessage || '').trim();
    if (!text) {
      return res.status(400).json({ error: 'userMessage is required.' });
    }

    const normalizedHistory = Array.isArray(history)
      ? history
          .slice(-8)
          .map((item) => ({
            role:
              item?.role === 'assistant' || item?.role === 'user'
                ? item.role
                : 'user',
            content: String(item?.content || '').slice(0, 800),
          }))
          .filter((m) => m.content.trim().length > 0)
      : [];

    const messages = [
      {
        role: 'system',
        content:
          'You are a concise school-selection assistant. Keep responses short, practical, and under 120 Chinese characters unless user asks for details.',
      },
      {
        role: 'system',
        content: String(appContext || '').slice(0, 1000),
      },
      ...normalizedHistory,
      { role: 'user', content: text.slice(0, 1000) },
    ];

    const qwenResp = await fetch(QWEN_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${DASHSCOPE_API_KEY}`,
      },
      body: JSON.stringify({
        model: QWEN_MODEL,
        messages,
        temperature: 0.2,
        max_tokens: 160,
        stream: false,
      }),
    });

    if (!qwenResp.ok) {
      const detail = await safeText(qwenResp);
      return res.status(qwenResp.status).json({
        error: `Qwen API failed with status ${qwenResp.status}`,
        detail,
      });
    }

    const data = await qwenResp.json();
    const reply =
      data?.choices?.[0]?.message?.content?.toString()?.trim() || '';

    if (!reply) {
      return res.status(502).json({ error: 'Empty reply from Qwen.' });
    }

    return res.json({ reply });
  } catch (err) {
    return res.status(500).json({
      error: 'Proxy internal error.',
      detail: err instanceof Error ? err.message : String(err),
    });
  }
});

app.listen(port, () => {
  console.log(`AI proxy listening on :${port}`);
});

async function safeText(response) {
  try {
    return await response.text();
  } catch {
    return '';
  }
}
