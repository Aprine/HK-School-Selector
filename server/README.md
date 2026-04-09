# AI Proxy Backend (Qwen via DashScope)

## 1) Run locally
```bash
cd server
npm install
```

Create `.env` from `.env.example`, then run:
```bash
npm start
```

Health check:
```bash
GET http://localhost:8080/health
```

Chat endpoint:
```bash
POST http://localhost:8080/ai/chat
Content-Type: application/json

{
  "history": [{"role":"user","content":"hello"}],
  "userMessage": "帮我找最近的小学",
  "appContext": "Current filter context: district=All Districts, type=All Types"
}
```

Response:
```json
{"reply":"..."}
```

## 2) Deploy on Render (recommended)
1. Push `server/` code to your GitHub repo.
2. Create a new **Web Service** in Render.
3. Root Directory: `server`
4. Build Command: `npm install`
5. Start Command: `npm start`
6. Add environment variables:
   - `DASHSCOPE_API_KEY`
   - `QWEN_MODEL` (optional, default `qwen-turbo`)
   - `QWEN_ENDPOINT` (optional)
7. Deploy and copy service URL, e.g. `https://xxx.onrender.com`

## 3) Connect Flutter app
Run Flutter with:
```bash
flutter run -d chrome --dart-define=AI_PROXY_URL=https://xxx.onrender.com/ai/chat
```

Do not put `DASHSCOPE_API_KEY` in Flutter app.
