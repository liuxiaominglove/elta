const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;
const TOKEN_TTL = 30 * 60 * 1000; // 30 分钟有效期

// 生成限时 token（HMAC 签名，服务端无状态验证）
function createToken() {
  const expires = Date.now() + TOKEN_TTL;
  const payload = expires.toString();
  const sig = crypto.createHmac('sha256', ADMIN_PASSWORD).update(payload).digest('hex');
  return Buffer.from(`${expires}:${sig}`).toString('base64');
}

// 验证 token：检查是否过期 + 签名是否匹配
function verifyToken(token) {
  try {
    const decoded = Buffer.from(token, 'base64').toString('utf8');
    const [expiresStr, ...sigParts] = decoded.split(':');
    const expires = parseInt(expiresStr, 10);
    const sig = sigParts.join(':');
    if (isNaN(expires) || Date.now() > expires) return false;
    const expected = crypto.createHmac('sha256', ADMIN_PASSWORD).update(expires.toString()).digest('hex');
    return sig === expected;
  } catch {
    return false;
  }
}

module.exports = async (req, res) => {
  // ---------- CORS ----------
  const allowedOrigin = 'https://elta-seven.vercel.app';
  const origin = req.headers.origin || '';
  if (origin.startsWith(allowedOrigin) || origin.startsWith('http://localhost')) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  } else {
    res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  }
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Vary', 'Origin');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // ---------- CSRF 防护：检查 Origin / Referer ----------
  const referer = req.headers.referer || '';
  const originHeader = req.headers.origin || '';
  const sameOrigin = originHeader.startsWith(allowedOrigin) || originHeader.startsWith('http://localhost');
  const sameReferer = referer.startsWith(allowedOrigin) || referer.startsWith('http://localhost');
  // 允许无 Origin 的请求（curl/Postman），但有 Origin 时必须匹配
  if (originHeader && !sameOrigin && !referer && !sameReferer && !originHeader.startsWith('null')) {
    return res.status(403).json({ error: '跨站请求被拒绝' });
  }

  // ---------- 环境变量校验 ----------
  if (!ADMIN_PASSWORD) {
    return res.status(500).json({ error: '服务器未配置 ADMIN_PASSWORD' });
  }
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return res.status(500).json({ error: '服务器未配置 Supabase 环境变量' });
  }

  // ---------- 解析请求体 ----------
  let body = req.body || '{}';
  if (Buffer.isBuffer(body)) body = body.toString('utf8');
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (e) { body = {}; }
  }

  const { password, token, action, feedbackId, reply } = body || {};

  // ---------- 登录：用密码换取限时 token ----------
  if (action === 'login') {
    return handleLogin(password, req, res);
  }

  // ---------- 业务操作：用 token 鉴权 ----------
  if (!token) {
    return res.status(401).json({ error: '未提供认证凭据' });
  }
  if (!verifyToken(token)) {
    return res.status(401).json({ error: '登录已过期，请重新登录' });
  }

  // ---------- Supabase 请求头 ----------
  const headers = {
    'Content-Type': 'application/json',
    'apikey': SUPABASE_SERVICE_ROLE_KEY,
    'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
    'Prefer': 'return=representation'
  };

  try {
    switch (action) {
      case 'list': {
        const response = await fetch(
          `${SUPABASE_URL}/rest/v1/feedback?select=*&order=created_at.desc&limit=100`,
          { method: 'GET', headers }
        );
        const data = await response.json();
        if (!response.ok) return res.status(500).json({ error: data.message || '查询失败' });
        return res.json(data);
      }

      case 'approve': {
        const response = await fetch(
          `${SUPABASE_URL}/rest/v1/feedback?id=eq.${feedbackId}`,
          { method: 'PATCH', headers, body: JSON.stringify({ status: 'approved' }) }
        );
        if (!response.ok) {
          const data = await response.json();
          return res.status(500).json({ error: data.message || '通过失败' });
        }
        return res.json({ success: true });
      }

      case 'reject': {
        const response = await fetch(
          `${SUPABASE_URL}/rest/v1/feedback?id=eq.${feedbackId}`,
          { method: 'PATCH', headers, body: JSON.stringify({ status: 'rejected' }) }
        );
        if (!response.ok) {
          const data = await response.json();
          return res.status(500).json({ error: data.message || '拒绝失败' });
        }
        return res.json({ success: true });
      }

      case 'reply': {
        const response = await fetch(
          `${SUPABASE_URL}/rest/v1/feedback?id=eq.${feedbackId}`,
          { method: 'PATCH', headers, body: JSON.stringify({ admin_reply: reply, status: 'approved' }) }
        );
        if (!response.ok) {
          const data = await response.json();
          return res.status(500).json({ error: data.message || '回复失败' });
        }
        return res.json({ success: true });
      }

      default:
        return res.status(400).json({ error: '未知操作' });
    }
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
};

// ---------- 登录处理（含速率限制） ----------
async function handleLogin(password, req, res) {
  if (!password) {
    return res.status(400).json({ error: '请输入密码' });
  }

  // 速率限制：5 次失败 / 1 分钟 → 锁定 5 分钟
  const RATELIMIT_MAX = 5;
  const RATELIMIT_WINDOW_MS = 60 * 1000;
  const RATELIMIT_LOCK_MS = 5 * 60 * 1000;
  const clientIP = req.headers['x-forwarded-for'] || req.headers['x-real-ip'] || req.socket?.remoteAddress || 'unknown';
  const rateLimitFile = path.join('/tmp', `elta_ratelimit_${clientIP.replace(/[^a-fA-F0-9:.]/g, '_')}.json`);

  let rateData = { count: 0, lockUntil: 0 };
  try {
    const raw = fs.readFileSync(rateLimitFile, 'utf8');
    rateData = JSON.parse(raw);
  } catch (_) {}

  const now = Date.now();

  if (rateData.lockUntil > now) {
    const remainSec = Math.ceil((rateData.lockUntil - now) / 1000);
    return res.status(429).json({ error: `登录尝试过于频繁，请在 ${remainSec} 秒后重试` });
  }

  if (rateData.count > 0 && (now - (rateData._lastAttempt || 0)) > RATELIMIT_WINDOW_MS) {
    rateData.count = 0;
  }

  if (password !== ADMIN_PASSWORD) {
    rateData.count += 1;
    rateData._lastAttempt = now;
    if (rateData.count >= RATELIMIT_MAX) {
      rateData.lockUntil = now + RATELIMIT_LOCK_MS;
      rateData.count = 0;
      try { fs.writeFileSync(rateLimitFile, JSON.stringify(rateData)); } catch (_) {}
      return res.status(429).json({ error: '登录尝试过于频繁，请 5 分钟后重试' });
    }
    try { fs.writeFileSync(rateLimitFile, JSON.stringify(rateData)); } catch (_) {}
    const remaining = RATELIMIT_MAX - rateData.count;
    return res.status(401).json({ error: `密码错误（还可尝试 ${remaining} 次）` });
  }

  // 登录成功，清除速率记录
  try { fs.unlinkSync(rateLimitFile); } catch (_) {}

  // 签发限时 token（30 分钟有效）
  const authToken = createToken();
  return res.json({ token: authToken });
}
