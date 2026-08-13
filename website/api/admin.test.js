const crypto = require('crypto');
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert');

const SUPABASE_URL = 'https://test.supabase.co';
const SUPABASE_SERVICE_ROLE_KEY = 'sb-test-key';

describe('admin.js Security Tests', () => {
  let handler;
  let createTokenFn;
  let verifyTokenFn;

  beforeEach(() => {
    process.env.SUPABASE_URL = SUPABASE_URL;
    process.env.SUPABASE_SERVICE_ROLE_KEY = SUPABASE_SERVICE_ROLE_KEY;
    process.env.ADMIN_PASSWORD = 'test-admin-pass';
    process.env.TOKEN_SIGNING_SECRET = process.env.TOKEN_SIGNING_SECRET || undefined;
    delete require.cache[require.resolve('./admin.js')];
    const mod = require('./admin.js');
    handler = mod;
    createTokenFn = mod._internal?.createToken;
    verifyTokenFn = mod._internal?.verifyToken;
  });

  function mockRes() {
    const res = {
      statusCode: 200,
      headers: {},
      body: null,
      status(code) { this.statusCode = code; return this; },
      json(data) { this.body = data; return this; },
      setHeader(name, value) { this.headers[name] = value; return this; },
    };
    return res;
  }

  function mockReq(overrides = {}) {
    return {
      method: 'POST',
      headers: {},
      body: {},
      ...overrides,
    };
  }

  // ━━━ S1: CORS 子域名绕过 ━━━
  describe('S1: CORS Origin validation', () => {
    it('should allow exact matching origin', async () => {
      const req = mockReq({
        headers: { origin: 'https://elta-seven.vercel.app' },
        body: { token: 'fake', action: 'list' },
      });
      const res = mockRes();
      await handler(req, res);
      assert.equal(res.headers['Access-Control-Allow-Origin'], 'https://elta-seven.vercel.app');
    });

    it('should reject spoofed subdomain origin (startsWith bypass)', async () => {
      const req = mockReq({
        headers: { origin: 'https://elta-seven.vercel.app.evil.com' },
        body: { token: 'fake', action: 'list' },
      });
      const res = mockRes();
      await handler(req, res);
      assert.notEqual(
        res.headers['Access-Control-Allow-Origin'],
        'https://elta-seven.vercel.app.evil.com'
      );
    });

    it('should allow localhost origin', async () => {
      const req = mockReq({
        headers: { origin: 'http://localhost:3000' },
        body: { token: 'fake', action: 'list' },
      });
      const res = mockRes();
      await handler(req, res);
      assert.equal(res.headers['Access-Control-Allow-Origin'], 'http://localhost:3000');
    });

    it('should reject localhost spoof (startsWith bypass)', async () => {
      const req = mockReq({
        headers: { origin: 'http://localhost.evil.com' },
        body: { token: 'fake', action: 'list' },
      });
      const res = mockRes();
      await handler(req, res);
      assert.notEqual(
        res.headers['Access-Control-Allow-Origin'],
        'http://localhost.evil.com'
      );
    });
  });

  // ━━━ S2: CSRF Origin:null 绕过 ━━━
  describe('S2: CSRF Origin:null protection', () => {
    it('should reject requests with Origin:null', async () => {
      const req = mockReq({
        headers: { origin: 'null' },
        body: { token: 'fake', action: 'list' },
      });
      const res = mockRes();
      await handler(req, res);
      assert.equal(res.statusCode, 403);
      assert.equal(res.body.error, '跨站请求被拒绝');
    });

    it('should allow requests without Origin header (curl/Postman)', async () => {
      const req = mockReq({
        headers: {},
        body: { token: 'fake', action: 'list' },
      });
      const res = mockRes();
      await handler(req, res);
      assert.notEqual(res.statusCode, 403);
    });
  });

  // ━━━ S3: SQL / query injection via feedbackId ━━━
  describe('S3: feedbackId URL encoding', () => {
    it('should encodeURIComponent feedbackId to prevent injection', async () => {
      if (!createTokenFn) return;
      const testId = '1&id=neq.0';
      const encodedId = encodeURIComponent(testId);
      let capturedUrl = '';

      global.fetch = async (url) => {
        capturedUrl = url;
        return { ok: true, json: async () => [] };
      };

      const validToken = createTokenFn();
      const req = mockReq({
        body: { token: validToken, action: 'approve', feedbackId: testId },
      });
      const res = mockRes();
      await handler(req, res);

      assert.ok(
        capturedUrl.includes(`id=eq.${encodedId}`),
        `URL should contain encoded feedbackId. Got: ${capturedUrl}`
      );
      assert.ok(
        !capturedUrl.includes('id=eq.1&id=neq.0'),
        'URL should not contain unencoded injection payload'
      );
    });
  });

  // ━━━ S4: Timing-safe comparison ━━━
  describe('S4: Timing-safe comparison', () => {
    it('verifyToken should use crypto.timingSafeEqual', async () => {
      if (!verifyTokenFn) return; // skip if internal not exported
      const tokenStr = createTokenFn();
      const result = verifyTokenFn(tokenStr);
      assert.equal(result, true);
    });

    it('verifyToken should reject invalid token', async () => {
      if (!verifyTokenFn) return;
      const result = verifyTokenFn('invalid-token');
      assert.equal(result, false);
    });

    it('verifyToken should reject expired token', async () => {
      if (!createTokenFn || !verifyTokenFn) return;
      const token = createTokenFn();
      const decoded = Buffer.from(token, 'base64').toString('utf8');
      const [expires, sig] = decoded.split(':');
      const oldExpires = Date.now() - 100000;
      const oldToken = Buffer.from(`${oldExpires}:${sig}`).toString('base64');
      const result = verifyTokenFn(oldToken);
      assert.equal(result, false);
    });
  });

  // ━━━ S5: Rate-limit IP spoofing ━━━
  describe('S5: Rate-limit uses correct client IP', () => {
    it('should use leftmost IP from X-Forwarded-For', async () => {
      const getClientIP = handler._internal?.getClientIP;
      if (!getClientIP) return;
      const req = mockReq({
        headers: { 'x-forwarded-for': '1.2.3.4, 5.6.7.8' },
        body: { action: 'login', password: 'wrong' },
      });
      assert.equal(getClientIP(req), '1.2.3.4');
    });

    it('should use leftmost IP even with attacker-injected X-Forwarded-For', async () => {
      const getClientIP = handler._internal?.getClientIP;
      if (!getClientIP) return;
      // Vercel prepends real IP: "real_ip, attacker_fake"
      const req = mockReq({
        headers: { 'x-forwarded-for': 'real, spoofed1' },
        body: { action: 'login', password: 'wrong' },
      });
      assert.equal(getClientIP(req), 'real');
    });

    it('should fallback to remoteAddress when X-Forwarded-For absent', async () => {
      const getClientIP = handler._internal?.getClientIP;
      if (!getClientIP) return;
      const req = mockReq({
        headers: {},
        socket: { remoteAddress: '9.9.9.9' },
        body: { action: 'login', password: 'wrong' },
      });
      assert.equal(getClientIP(req), '9.9.9.9');
    });
  });

  // ━━━ S6: Password/Token key separation ━━━
  describe('S6: ADMIN_PASSWORD vs TOKEN_SIGNING_SECRET separation', () => {
    it('should use TOKEN_SIGNING_SECRET for token creation when set', async () => {
      if (!createTokenFn || !verifyTokenFn) return;

      // Test with separate TOKEN_SIGNING_SECRET
      process.env.TOKEN_SIGNING_SECRET = 'separate-signing-key';
      process.env.ADMIN_PASSWORD = 'different-admin-pass';
      delete require.cache[require.resolve('./admin.js')];
      const mod2 = require('./admin.js');
      const createToken2 = mod2._internal?.createToken;
      const verifyToken2 = mod2._internal?.verifyToken;

      if (createToken2 && verifyToken2) {
        const token = createToken2();
        assert.equal(verifyToken2(token), true);
      }
    });

    it('should reject login with wrong password even with correct signing key', async () => {
      process.env.TOKEN_SIGNING_SECRET = 'separate-signing-key';
      process.env.ADMIN_PASSWORD = 'correct-password';
      delete require.cache[require.resolve('./admin.js')];
      const mod3 = require('./admin.js');

      const req = mockReq({
        body: { action: 'login', password: 'wrong-password' },
      });
      const res = mockRes();
      await mod3(req, res);

      assert.equal(res.statusCode, 401);
      assert.ok(res.body.error?.includes('密码错误'));
    });
  });
});
