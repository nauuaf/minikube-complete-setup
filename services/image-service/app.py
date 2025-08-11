from flask import Flask, jsonify, request
from datetime import datetime
import time
import os
import logging
from prometheus_client import Counter, Histogram, generate_latest

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Get secrets from environment
JWT_SECRET = os.getenv('JWT_SECRET')
IMAGE_SERVICE_TOKEN = os.getenv('IMAGE_SERVICE_TOKEN')
S3_ACCESS_KEY = os.getenv('S3_ACCESS_KEY')
S3_SECRET_KEY = os.getenv('S3_SECRET_KEY')
S3_BUCKET = os.getenv('S3_BUCKET')

# Log configuration
app.logger.info('🔐 Image Service Configuration:')
app.logger.info(f'  JWT Secret: {"✅ Configured" if JWT_SECRET else "❌ Missing"}')
app.logger.info(f'  Service Token: {"✅ Configured" if IMAGE_SERVICE_TOKEN else "❌ Missing"}')
app.logger.info(f'  S3 Credentials: {"✅ Configured" if S3_ACCESS_KEY else "❌ Missing"}')

# Track service start time
start_time = time.time()

# Prometheus metrics
request_count = Counter('image_requests_total', 'Total image processing requests', ['method', 'endpoint'])
processing_time = Histogram('image_processing_duration_seconds', 'Time to process images')

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'image-service',
        'version': os.getenv('VERSION', '1.0.0'),
        'uptime': time.time() - start_time
    })

@app.route('/ready')
def ready():
    """Readiness check endpoint"""
    # Check if all required secrets are configured
    is_ready = all([IMAGE_SERVICE_TOKEN, S3_ACCESS_KEY])
    
    if is_ready:
        return jsonify({'ready': True, 'message': 'Service ready'})
    else:
        return jsonify({'ready': False, 'message': 'Missing configuration'}), 503

@app.route('/')
def index():
    """Root endpoint"""
    return jsonify({
        'service': 'image-service',
        'version': '1.0.0',
        'endpoints': [
            '/health',
            '/ready',
            '/status',
            '/process',
            '/storage-info',
            '/metrics'
        ]
    })

@app.route('/status')
def status():
    """Service status endpoint"""
    request_count.labels('GET', '/status').inc()
    return jsonify({
        'operational': True,
        'timestamp': datetime.utcnow().isoformat(),
        'processed_images': 42,  # Mock metric
        'using_secrets': bool(IMAGE_SERVICE_TOKEN and S3_ACCESS_KEY)
    })

@app.route('/process', methods=['POST'])
def process():
    """Process image endpoint with authentication"""
    request_count.labels('POST', '/process').inc()
    
    # Simulate authentication check
    auth_header = request.headers.get('Authorization')
    if not auth_header and IMAGE_SERVICE_TOKEN:
        return jsonify({'error': 'Unauthorized'}), 401
    
    with processing_time.time():
        data = request.get_json() or {}
        image_name = data.get('image', 'unknown.jpg')
        user = data.get('user', 'anonymous')
        
        # Simulate image processing
        time.sleep(0.1)  # Simulate processing time
        
        result = {
            'processed': True,
            'image': image_name,
            'user': user,
            'operations': ['resize', 'compress', 'optimize'],
            'storage': {
                'provider': 'S3-compatible',
                'bucket': S3_BUCKET if S3_BUCKET else 'default-bucket',
                'configured': bool(S3_ACCESS_KEY)
            },
            'timestamp': datetime.utcnow().isoformat()
        }
    
    return jsonify(result)

@app.route('/storage-info')
def storage_info():
    """Storage configuration endpoint"""
    if not S3_ACCESS_KEY:
        return jsonify({
            'error': 'Storage not configured',
            'hint': 'S3 credentials missing from Kubernetes Secrets'
        }), 500
    
    return jsonify({
        'configured': True,
        'provider': 'S3-compatible',
        'bucket': S3_BUCKET or 'default-bucket',
        'region': os.getenv('S3_REGION', 'us-east-1'),
        'operations_available': ['upload', 'download', 'list', 'delete'],
        'message': 'Using S3 credentials from Kubernetes Secrets'
    })

@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(), 200, {'Content-Type': 'text/plain'}

# Error handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Endpoint not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port)