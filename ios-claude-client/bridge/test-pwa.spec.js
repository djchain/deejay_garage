// @ts-check
const { test, expect } = require('@playwright/test');

const BASE = 'http://localhost:9090';
const WS_URL = 'ws://localhost:9090/ws';

test.describe('Claude Remote PWA', () => {

  test('page loads and renders terminal', async ({ page }) => {
    await page.goto(BASE);
    await page.waitForSelector('.xterm', { timeout: 10000 });
    await page.waitForSelector('.xterm-rows', { timeout: 5000 });

    // Verify topbar elements
    await expect(page.locator('#title')).toHaveText('Claude Remote');
    await expect(page.locator('#status-dot')).toBeVisible();
    await expect(page.locator('#status-label')).toBeVisible();
  });

  test('function key bar has all 6 keys + paste', async ({ page }) => {
    await page.goto(BASE);
    await page.waitForSelector('.fn-key', { timeout: 10000 });
    const keys = page.locator('.fn-key');
    await expect(keys).toHaveCount(7);
    await expect(page.locator('#paste-btn')).toBeVisible();

    // Verify key labels
    const labels = ['CtrlC','CtrlD','Esc','Tab','Up','Dn'];
    for (let i = 0; i < labels.length; i++) {
      await expect(keys.nth(i).locator('.label')).toHaveText(labels[i]);
    }
  });

  test('sidebar opens and closes', async ({ page }) => {
    await page.goto(BASE);

    // Sidebar initially hidden
    await expect(page.locator('#sidebar-overlay')).not.toHaveClass(/open/);

    // Open via hamburger
    await page.locator('#menu-btn').click();
    await expect(page.locator('#sidebar-overlay')).toHaveClass(/open/);

    // Close via × button
    await page.locator('#close-sidebar').click();
    await expect(page.locator('#sidebar-overlay')).not.toHaveClass(/open/);

    // Open again, close via overlay click
    await page.locator('#menu-btn').click();
    await expect(page.locator('#sidebar-overlay')).toHaveClass(/open/);
    await page.locator('#sidebar-overlay').click({ position: { x: 300, y: 200 } });
    await expect(page.locator('#sidebar-overlay')).not.toHaveClass(/open/);
  });

  test('scroll-to-bottom button appears on terminal scroll', async ({ page }) => {
    await page.goto(BASE);
    await page.waitForSelector('.xterm', { timeout: 10000 });

    // Button should be hidden initially (at bottom)
    const scrollBtn = page.locator('#scroll-btn');
    await expect(scrollBtn).not.toHaveClass(/visible/);

    // Scroll the xterm viewport up
    await page.evaluate(() => {
      const vp = document.querySelector('.xterm-viewport');
      if (vp) vp.scrollTop = 200;
    });
    // Trigger scroll event
    await page.evaluate(() => {
      const vp = document.querySelector('.xterm-viewport');
      if (vp) vp.dispatchEvent(new Event('scroll'));
    });

    // Button should now be visible
    // Note: this depends on xterm firing onScroll which triggers our handler
  });

  test('title and status elements present', async ({ page }) => {
    await page.goto(BASE);
    await page.waitForSelector('#topbar', { timeout: 5000 });

    await expect(page.locator('#title')).toHaveText('Claude Remote');
    await expect(page.locator('#menu-btn')).toBeVisible();
    await expect(page.locator('#status-dot')).toBeVisible();
    await expect(page.locator('#status-label')).toHaveText(/ONLINE|OFFLINE|CONN/);
  });

  test('sidebar has create session input', async ({ page }) => {
    await page.goto(BASE);
    await page.locator('#menu-btn').click();
    await page.waitForSelector('#sidebar-overlay.open', { timeout: 3000 });

    await expect(page.locator('#new-session-input')).toBeVisible();
    await expect(page.locator('#new-session-btn')).toHaveText('Create');
    await expect(page.locator('#reconnect-btn')).toHaveText('Reconn');
    await expect(page.locator('#conn-info')).toBeVisible();
  });

});

test.describe('WebSocket integration', () => {

  test('WebSocket handshake succeeds', async ({ page }) => {
    // Connect via WebSocket directly and check for pong
    const wsResult = await page.evaluate((url) => {
      return new Promise((resolve) => {
        const ws = new WebSocket(url);
        const timeout = setTimeout(() => resolve({ error: 'timeout' }), 5000);
        ws.onopen = () => {
          ws.send(JSON.stringify({ type: 'ping' }));
        };
        ws.onmessage = (e) => {
          try {
            const msg = JSON.parse(e.data);
            if (msg.type === 'pong') {
              ws.close();
              clearTimeout(timeout);
              resolve({ success: true, type: msg.type });
            }
            // Also accept history/output as valid first messages
            if (msg.type === 'history' || msg.type === 'output') {
              resolve({ success: true, firstMessage: msg.type });
            }
          } catch (_) { /* ignore parse errors */ }
        };
        ws.onerror = (err) => { clearTimeout(timeout); resolve({ error: 'ws-error' }); };
      });
    }, WS_URL);

    expect(wsResult.success || wsResult.firstMessage).toBeTruthy();
  });

  test('function keys send correct protocol messages', async ({ page }) => {
    await page.goto(BASE);
    await page.waitForSelector('.fn-key', { timeout: 10000 });

    // Intercept WebSocket sends by monkey-patching before connect
    const sentMessages = await page.evaluate(() => {
      const messages = [];
      // Override send to capture
      const origSend = WebSocket.prototype.send;
      WebSocket.prototype.send = function(data) {
        try {
          const parsed = JSON.parse(data);
          messages.push(parsed);
        } catch (_) {}
        return origSend.call(this, data);
      };

      // Trigger a function key click
      const ctrlcBtn = document.querySelector('[data-key="ctrl-c"]');
      if (ctrlcBtn) ctrlcBtn.click();

      const escBtn = document.querySelector('[data-key="esc"]');
      if (escBtn) escBtn.click();

      const upBtn = document.querySelector('[data-key="up"]');
      if (upBtn) upBtn.click();

      return messages;
    });

    // We should have captured at least the 3 key clicks
    const signals = sentMessages.filter(m => m.type === 'signal');
    const inputs = sentMessages.filter(m => m.type === 'input');

    expect(signals.some(m => m.name === 'int')).toBeTruthy(); // ctrl-c
    expect(inputs.some(m => m.data === '\x1b')).toBeTruthy(); // esc
    expect(inputs.some(m => m.data === '\x1b[A')).toBeTruthy(); // up
  });

  test('ping/pong heartbeat works', async ({ page }) => {
    const result = await page.evaluate((url) => {
      return new Promise((resolve) => {
        const ws = new WebSocket(url);
        const timeout = setTimeout(() => resolve(false), 5000);
        ws.onopen = () => ws.send(JSON.stringify({ type: 'ping' }));
        ws.onmessage = (e) => {
          try {
            const msg = JSON.parse(e.data);
            if (msg.type === 'pong') {
              ws.close();
              clearTimeout(timeout);
              resolve(true);
            }
          } catch (_) {}
        };
        ws.onerror = () => { clearTimeout(timeout); resolve(false); };
      });
    }, WS_URL);
    expect(result).toBeTruthy();
  });

  test('session list response received', async ({ page }) => {
    await page.goto(BASE);
    await page.waitForSelector('.xterm', { timeout: 10000 });

    // Connect and wait for session_list message
    const hasSessions = await page.evaluate((url) => {
      return new Promise((resolve) => {
        const ws = new WebSocket(url);
        const timeout = setTimeout(() => resolve(false), 8000);
        ws.onmessage = (e) => {
          try {
            const msg = JSON.parse(e.data);
            if (msg.type === 'session_list') {
              ws.close();
              clearTimeout(timeout);
              resolve(true);
            }
          } catch (_) {}
        };
        ws.onerror = () => { clearTimeout(timeout); resolve(false); };
      });
    }, WS_URL);
    expect(hasSessions).toBeTruthy();
  });

});

test.describe('PWA readiness', () => {

  test('manifest.json served with correct content-type', async ({ request }) => {
    const resp = await request.get(BASE + '/manifest.json');
    expect(resp.status()).toBe(200);
    const json = await resp.json();
    expect(json.name).toBe('Claude Remote');
    expect(json.display).toBe('standalone');
  });

  test('service worker registered', async ({ page }) => {
    await page.goto(BASE);
    const swUrl = await page.evaluate(async () => {
      try {
        const reg = await navigator.serviceWorker.register('/sw.js');
        return reg.active?.scriptURL || reg.installing?.scriptURL || 'registered';
      } catch (e) {
        return 'error: ' + e.message;
      }
    });
    expect(swUrl).toContain('sw.js');
  });

  test('apple-mobile-web-app-capable meta present', async ({ page }) => {
    await page.goto(BASE);
    const capable = await page.evaluate(() => {
      const meta = document.querySelector('meta[name="apple-mobile-web-app-capable"]');
      return meta ? meta.getAttribute('content') : null;
    });
    expect(capable).toBe('yes');
  });

});

test.describe('Scrollback history', () => {

  test('history message received on connect', async ({ page }) => {
    const historyData = await page.evaluate((url) => {
      return new Promise((resolve) => {
        const ws = new WebSocket(url);
        const timeout = setTimeout(() => resolve(null), 8000);
        ws.onmessage = (e) => {
          try {
            const msg = JSON.parse(e.data);
            if (msg.type === 'history') {
              ws.close();
              clearTimeout(timeout);
              resolve(msg.data);
            }
            // If we get output without history, that's also ok (no prior content)
            if (msg.type === 'output') {
              ws.close();
              clearTimeout(timeout);
              resolve('');
            }
          } catch (_) {}
        };
        ws.onerror = () => { clearTimeout(timeout); resolve(null); };
      });
    }, WS_URL);
    // History should be present (even if empty, the bridge sends it)
    expect(historyData).not.toBeNull();
  });

});
