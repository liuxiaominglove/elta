const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD;

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

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

  if (password !== ADMIN_PASSWORD) {
    return res.status(401).json({ error: '密码错误' });
  }

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
