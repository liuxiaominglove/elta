const { createClient } = require('@supabase/supabase-js');

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

  const { password, action, feedbackId, reply } = req.body || {};

  if (password !== process.env.ADMIN_PASSWORD) {
    return res.status(401).json({ error: '密码错误' });
  }

  const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY
  );

  try {
    switch (action) {
      case 'list': {
        const { data, error } = await supabase
          .from('feedback')
          .select('*')
          .order('created_at', { ascending: false })
          .limit(100);
        if (error) return res.status(500).json({ error: error.message });
        return res.json(data);
      }

      case 'approve': {
        const { error } = await supabase
          .from('feedback')
          .update({ status: 'approved' })
          .eq('id', feedbackId);
        if (error) return res.status(500).json({ error: error.message });
        return res.json({ success: true });
      }

      case 'reject': {
        const { error } = await supabase
          .from('feedback')
          .update({ status: 'rejected' })
          .eq('id', feedbackId);
        if (error) return res.status(500).json({ error: error.message });
        return res.json({ success: true });
      }

      case 'reply': {
        const { error } = await supabase
          .from('feedback')
          .update({ admin_reply: reply, status: 'approved' })
          .eq('id', feedbackId);
        if (error) return res.status(500).json({ error: error.message });
        return res.json({ success: true });
      }

      default:
        return res.status(400).json({ error: '未知操作' });
    }
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
};
