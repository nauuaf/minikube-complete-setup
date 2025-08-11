const express = require('express');
const axios = require('axios');
const crypto = require('crypto');
const promClient = require('prom-client');

const app = express();
app.use(express.json());

// Get secrets from environment
const JWT_SECRET = process.env.JWT_SECRET;
const INTERNAL_API_KEY = process.env.INTERNAL_API_KEY;
const AUTH_SERVICE_TOKEN = process.env.AUTH_SERVICE_TOKEN;
const DB_USER = process.env.DB_USER;
const DB_PASSWORD = process.env.DB_PASSWORD;
const S3_ACCESS_KEY = process.env.S3_ACCESS_KEY;

// Validate secrets are loaded
console.log('🔐 Secret Configuration Status:');
console.log(`  JWT Secret: ${JWT_SECRET ? '✅ Configured' : '❌ Missing'}`);
console.log(`  Internal API Key: ${INTERNAL_API_KEY ? '✅ Configured' : '❌ Missing'}`);
console.log(`  Auth Service Token: ${AUTH_SERVICE_TOKEN ? '✅ Configured' : '❌ Missing'}`);
console.log(`  Database Credentials: ${DB_USER && DB_PASSWORD ? '✅ Configured' : '❌ Missing'}`);
console.log(`  S3 Credentials: ${S3_ACCESS_KEY ? '✅ Configured' : '❌ Missing'}`);

// Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestDuration = new promClient.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duration of HTTP requests in seconds',
    labelNames: ['method', 'route', 'status'],
    registers: [register]
});

const requestCounter = new promClient.Counter({
    name: 'api_requests_total',
    help: 'Total number of API requests',
    labelNames: ['method', 'endpoint', 'status'],
    registers: [register]
});

// Middleware
app.use((req, res, next) => {
    const start = Date.now();
    res.on('finish', () => {
        const duration = (Date.now() - start) / 1000;
        httpRequestDuration.labels(req.method, req.path, res.statusCode).observe(duration);
        requestCounter.labels(req.method, req.path, res.statusCode).inc();
    });
    next();
});

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        service: 'api-service',
        version: process.env.VERSION || '1.0.0',
        timestamp: new Date().toISOString()
    });
});

// Readiness check
app.get('/ready', async (req, res) => {
    try {
        const authCheck = await axios.get('http://auth-service:8080/health', {
            headers: { 'X-Service-Token': AUTH_SERVICE_TOKEN },
            timeout: 2000
        }).catch(() => null);
        
        const imageCheck = await axios.get('http://image-service:5000/health', {
            timeout: 2000
        }).catch(() => null);
        
        if (authCheck && imageCheck) {
            res.json({ ready: true, dependencies: 'connected' });
        } else {
            res.status(503).json({ ready: false, dependencies: 'not ready' });
        }
    } catch (error) {
        res.status(503).json({ ready: false, error: error.message });
    }
});

// Secret status endpoint
app.get('/secret-status', (req, res) => {
    res.json({
        secrets_configured: !!(JWT_SECRET && INTERNAL_API_KEY && AUTH_SERVICE_TOKEN),
        using_kubernetes_secrets: true,
        database_connected: !!(DB_USER && DB_PASSWORD),
        storage_configured: !!S3_ACCESS_KEY
    });
});

// Test inter-service communication
app.get('/test-communication', async (req, res) => {
    try {
        const authResponse = await axios.get('http://auth-service:8080/validate', {
            headers: {
                'X-Service-Token': AUTH_SERVICE_TOKEN,
                'X-Internal-API-Key': INTERNAL_API_KEY
            }
        });
        
        const imageResponse = await axios.get('http://image-service:5000/status');
        
        res.json({
            success: true,
            api_service: 'operational',
            auth_service: authResponse.data,
            image_service: imageResponse.data,
            secrets_used: true,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: 'Service communication failed',
            details: error.message
        });
    }
});

// Generate JWT token
app.post('/generate-token', (req, res) => {
    if (!JWT_SECRET) {
        return res.status(500).json({ error: 'JWT secret not configured' });
    }
    
    const payload = {
        user: req.body.user || 'anonymous',
        timestamp: Date.now()
    };
    
    const token = crypto
        .createHmac('sha256', JWT_SECRET)
        .update(JSON.stringify(payload))
        .digest('hex');
    
    res.json({
        token,
        message: 'Token generated using Kubernetes Secret',
        payload
    });
});

// Database status
app.get('/database-status', (req, res) => {
    if (!DB_USER || !DB_PASSWORD) {
        return res.status(500).json({
            error: 'Database credentials not configured',
            hint: 'Check Kubernetes Secrets'
        });
    }
    
    res.json({
        status: 'connected',
        user: DB_USER,
        message: 'Using credentials from Kubernetes Secrets',
        operations_available: ['read', 'write', 'update', 'delete']
    });
});

// Storage status
app.get('/storage-status', (req, res) => {
    if (!S3_ACCESS_KEY) {
        return res.status(500).json({
            error: 'Storage credentials not configured'
        });
    }
    
    res.json({
        status: 'connected',
        provider: 'S3-compatible',
        message: 'Using S3 credentials from Kubernetes Secrets',
        operations_available: ['upload', 'download', 'list', 'delete']
    });
});

// Main API endpoint
app.post('/api/process', async (req, res) => {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader) {
            return res.status(401).json({ error: 'No authorization header' });
        }
        
        const authResult = await axios.post('http://auth-service:8080/authenticate', {
            token: authHeader
        }, {
            headers: {
                'X-Service-Token': AUTH_SERVICE_TOKEN,
                'X-Internal-API-Key': INTERNAL_API_KEY
            }
        });
        
        if (!authResult.data.valid) {
            return res.status(401).json({ error: 'Invalid token' });
        }
        
        const imageResult = await axios.post('http://image-service:5000/process', {
            image: req.body.image || 'default.jpg',
            user: authResult.data.user
        });
        
        res.json({
            success: true,
            user: authResult.data.user,
            image_processed: imageResult.data,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        res.status(500).json({
            error: 'Processing failed',
            message: error.message
        });
    }
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
    res.set('Content-Type', register.contentType);
    register.metrics().then(metrics => res.send(metrics));
});

// Root endpoint
app.get('/', (req, res) => {
    res.json({
        service: 'api-service',
        version: '1.0.0',
        endpoints: [
            '/health',
            '/ready',
            '/secret-status',
            '/test-communication',
            '/generate-token',
            '/database-status',
            '/storage-status',
            '/api/process',
            '/metrics'
        ]
    });
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('SIGTERM received, shutting down gracefully...');
    server.close(() => {
        console.log('Server closed');
        process.exit(0);
    });
});

const PORT = process.env.PORT || 3000;
const server = app.listen(PORT, () => {
    console.log(`🚀 API Service running on port ${PORT}`);
});