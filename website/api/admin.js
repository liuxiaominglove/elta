const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;

module.exports = async (req, res) => {
  const allowedOrigin = 'https://elta-seven.vercel.app';
  const origin = req.headers.origin || req.headers.referer || '';
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

  // Vercel Node function 不会自动解析 JSON body，需要手动解析
  let body = req.body || '{}';
  if (Buffer.isBuffer(body)) body = body.toString('utf8');
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (e) { body = {}; }
  }

  const { password, action, feedbackId, reply } = body || {};

  if (!ADMIN_PASSWORD) {
    return res.status(500).json({ error: '服务器未配置 ADMIN_PASSWORD' });
  }
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return res.status(500).json({ error: '服务器未配置 Supabase 环境变量' });
  }

  // ---------- 登录速率限制 ----------
  // 5 次失败 / 1 分钟 → 锁定 5 分钟
  const RATELIMIT_MAX = 5;
  const RATELIMIT_WINDOW_MS = 60 * 1000;
  const RATELIMIT_LOCK_MS = 5 * 60 * 1000;
  const clientIP = req.headers['x-forwarded-for'] || req.headers['x-real-ip'] || req.socket?.remoteAddress || 'unknown';

  // 使用文件系统的 /tmp/ 目录做跨 cold-start 持久化
  const fs = require('fs');
  const path = require('path');
  const rateLimitFile = path.join('/tmp', `elta_ratelimit_${clientIP.replace(/[^a-fA-F0-9:.]/g, '_')}.json`);

  let rateData = { count: 0, lockUntil: 0 };
  try {
    const raw = fs.readFileSync(rateLimitFile, 'utf8');
    rateData = JSON.parse(raw);
  } catch (_) { /* 文件不存在，使用默认值 */ }

  const now = Date.now();

  // 如果还在锁定期内
  if (rateData.lockUntil > now) {
    const remainSec = Math.ceil((rateData.lockUntil - now) / 1000);
    return res.status(429).json({ error: `登录尝试过于频繁，请在 ${remainSec} 秒后重试` });
  }

  // 窗口已过期，重置计数
  if (rateData.count > 0 && (now - (rateData._lastAttempt || 0)) > RATELIMIT_WINDOW_MS) {
    rateData.count = 0;
  }

  if (password !== ADMIN_PASSWORD) {
    rateData.count += 1;
    rateData._lastAttempt = now;
    if (rateData.count >= RATELIMIT_MAX) {
      rateData.lockUntil = now + RATELIMIT_LOCK_MS;
      rateData.count = 0;
      fs.writeFileSync(rateLimitFile, JSON.stringify(rateData));
      return res.status(429).json({ error: '登录尝试过于频繁，请 5 分钟后重试' });
    }
    fs.writeFileSync(rateLimitFile, JSON.stringify(rateData));
    const remaining = RATELIMIT_MAX - rateData.count;
    return res.status(401).json({ error: `密码错误（还可尝试 ${remaining} 次）` });
  }

  // 登录成功，清除速率记录
  try { fs.unlinkSync(rateLimitFile); } catch (_) {}

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
