import express from 'express';
import { createProxyMiddleware } from 'http-proxy-middleware';
import { verifyBearer } from './auth.js';

const app = express();
const PORT = Number(process.env.PORT || 8080);

const AUTH_URL = process.env.AUTH_SERVICE_URL || 'http://auth-service:3001';
const UPLOAD_URL = process.env.UPLOAD_SERVICE_URL || 'http://upload-service:3003';
const FILES_URL = process.env.FILES_SERVICE_URL || 'http://files-service:3002';
const NOTIF_URL =
  process.env.NOTIFICATION_SERVICE_URL || 'http://notification-service:3004';

// ---- CORS ----
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', req.headers.origin || '*');
  res.setHeader('Vary', 'Origin');
  res.setHeader(
    'Access-Control-Allow-Methods',
    'GET,POST,PATCH,PUT,DELETE,OPTIONS'
  );
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Authorization, Content-Type'
  );

  if (req.method === 'OPTIONS') {
    return res.sendStatus(204);
  }

  next();
});

const addCorsToProxyRes = (proxyRes, req) => {
  proxyRes.headers['access-control-allow-origin'] =
    req.headers.origin || '*';

  proxyRes.headers['vary'] = 'Origin';
};

// ---- Health ----
app.get('/healthz', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'gateway',
  });
});

app.get('/readyz', async (_req, res) => {
  const targets = {
    auth: AUTH_URL,
    files: FILES_URL,
    upload: UPLOAD_URL,
    notification: NOTIF_URL,
  };

  const checks = {};

  await Promise.all(
    Object.entries(targets).map(async ([name, url]) => {
      try {
        const ctrl = new AbortController();
        const timeout = setTimeout(() => ctrl.abort(), 2000);

        const response = await fetch(`${url}/healthz`, {
          signal: ctrl.signal,
        });

        clearTimeout(timeout);

        checks[name] = response.ok
          ? 'ok'
          : `status ${response.status}`;
      } catch (error) {
        checks[name] = String(error.message || error);
      }
    })
  );

  const ready = Object.values(checks).every(
    (value) => value === 'ok'
  );

  res.status(ready ? 200 : 503).json({
    status: ready ? 'ready' : 'not-ready',
    checks,
  });
});

app.get('/', (_req, res) => {
  res.json({
    service: 'CloudVault API gateway',
    routes: {
      'POST /auth/register': 'public',
      'POST /auth/login': 'public',
      'GET /auth/verify': 'public',
      'POST /upload': 'JWT required',
      'GET /files, GET /files/:id': 'JWT required',
      'GET /notifications': 'JWT required',
    },
  });
});

// ---- Authentication ----
function requireAuth(req, res, next) {
  try {
    const { userId } = verifyBearer(
      req.headers.authorization
    );

    req.userId = userId;

    next();
  } catch (error) {
    res.status(401).json({
      error: 'unauthorized',
      detail: String(error.message || error),
    });
  }
}

app.use('/upload', requireAuth);
app.use('/files', requireAuth);
app.use('/notifications', requireAuth);

const injectUser = (proxyReq, req) => {
  if (req.userId) {
    proxyReq.setHeader('x-user-id', req.userId);
  }
};

// ---- Reverse proxy routing ----

// Auth
app.use(
  createProxyMiddleware({
    pathFilter: '/auth',
    target: AUTH_URL,
    changeOrigin: true,
    pathRewrite: {
      '^/auth': '',
    },
    on: {
      proxyRes: addCorsToProxyRes,
    },
  })
);

// Upload
app.use(
  createProxyMiddleware({
    pathFilter: '/upload',
    target: UPLOAD_URL,
    changeOrigin: true,
    on: {
      proxyReq: injectUser,
      proxyRes: addCorsToProxyRes,
    },
  })
);

// Files
app.use(
  createProxyMiddleware({
    pathFilter: '/files',
    target: FILES_URL,
    changeOrigin: true,
    on: {
      proxyReq: injectUser,
      proxyRes: addCorsToProxyRes,
    },
  })
);

// Notifications
app.use(
  createProxyMiddleware({
    pathFilter: '/notifications',
    target: NOTIF_URL,
    changeOrigin: true,
    on: {
      proxyReq: injectUser,
      proxyRes: addCorsToProxyRes,
    },
  })
);

app.listen(PORT, () => {
  console.log(`gateway listening on :${PORT}`);
});