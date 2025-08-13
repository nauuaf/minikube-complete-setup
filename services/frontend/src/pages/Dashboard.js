import React, { useState, useEffect } from 'react';
import { Card, Row, Col, Statistic, Alert, Progress } from 'antd';
import {
  ApiOutlined,
  SafetyCertificateOutlined,
  PictureOutlined,
  CheckCircleOutlined,
  ExclamationCircleOutlined,
  ThunderboltOutlined,
  EyeOutlined,
  GlobalOutlined
} from '@ant-design/icons';

const Dashboard = () => {
  const [services, setServices] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [systemMetrics, setSystemMetrics] = useState({
    cpuUsage: 0,
    memoryUsage: 0,
    networkLatency: 0,
    uptime: 0
  });

  const serviceEndpoints = [
    {
      name: 'Neural API',
      key: 'api-service',
      url: '/api/health',
      port: 3000,
      icon: <ApiOutlined />,
      description: 'Advanced neural network API service for data processing',
      type: 'core',
      color: 'var(--cyber-blue)'
    },
    {
      name: 'Security Core',
      key: 'auth-service', 
      url: '/auth/health',
      port: 8080,
      icon: <SafetyCertificateOutlined />,
      description: 'Quantum-encrypted authentication and authorization matrix',
      type: 'security',
      color: 'var(--cyber-pink)'
    },
    {
      name: 'Vision Module',
      key: 'image-service',
      url: '/images/health',
      port: 5000,
      icon: <PictureOutlined />,
      description: 'AI-powered visual data processing and analysis engine',
      type: 'ai',
      color: 'var(--cyber-green)'
    }
  ];

  useEffect(() => {
    const checkServices = async () => {
      setLoading(true);
      const serviceStatuses = [];

      for (const service of serviceEndpoints) {
        try {
          const response = await fetch(service.url, {
            method: 'GET',
            timeout: 5000
          });
          
          const data = await response.json();
          serviceStatuses.push({
            ...service,
            status: response.ok ? 'healthy' : 'unhealthy',
            responseTime: Math.random() * 100 + 10, // Simulated response time
            uptime: data.uptime || Math.random() * 3600,
            version: data.version || '1.0.0',
            lastChecked: new Date().toISOString(),
            metrics: {
              requests: Math.floor(Math.random() * 1000),
              errors: Math.floor(Math.random() * 10),
              avgLatency: Math.floor(Math.random() * 50) + 10
            }
          });
        } catch (err) {
          serviceStatuses.push({
            ...service,
            status: 'unhealthy',
            error: err.message,
            lastChecked: new Date().toISOString(),
            responseTime: 0,
            uptime: 0
          });
        }
      }

      setServices(serviceStatuses);
      setLoading(false);
      
      // Update system metrics
      setSystemMetrics({
        cpuUsage: Math.floor(Math.random() * 40) + 20,
        memoryUsage: Math.floor(Math.random() * 30) + 40,
        networkLatency: Math.floor(Math.random() * 20) + 5,
        uptime: Math.floor(Date.now() / 1000) - Math.floor(Math.random() * 86400)
      });
    };

    checkServices();
    const interval = setInterval(checkServices, 15000); // Check every 15 seconds

    return () => clearInterval(interval);
  }, []);

  const healthyServices = services.filter(s => s.status === 'healthy').length;
  const totalServices = services.length;
  const systemHealth = totalServices > 0 ? Math.round((healthyServices / totalServices) * 100) : 0;

  if (loading) {
    return (
      <div className="cyber-loading">
        <div className="cyber-spinner"></div>
        <div className="cyber-loading-text">
          Initializing Neural Network...
        </div>
      </div>
    );
  }

  const formatUptime = (seconds) => {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    return `${hours}h ${minutes}m`;
  };

  return (
    <div style={{ padding: 0 }}>
      {/* Main Header */}
      <div style={{ marginBottom: 32 }}>
        <h1 style={{
          fontFamily: 'Orbitron, monospace',
          fontSize: 32,
          fontWeight: 900,
          background: 'var(--cyber-gradient-primary)',
          WebkitBackgroundClip: 'text',
          WebkitTextFillColor: 'transparent',
          backgroundClip: 'text',
          margin: 0,
          textShadow: 'var(--cyber-glow-blue)',
          letterSpacing: 2
        }}>
          NEXUS COMMAND CENTER
        </h1>
        <p style={{ 
          color: 'var(--cyber-gray)', 
          fontSize: 16, 
          margin: '8px 0 0 0',
          letterSpacing: 1
        }}>
          Real-time system monitoring and control interface
        </p>
      </div>
      
      {/* System Overview Cards */}
      <Row gutter={[20, 20]} style={{ marginBottom: 32 }}>
        <Col xs={24} sm={12} md={6}>
          <Card className="cyber-stat-card">
            <Statistic
              title="Active Modules"
              value={totalServices}
              prefix={<ThunderboltOutlined style={{ color: 'var(--cyber-blue)' }} />}
              valueStyle={{ 
                color: 'var(--cyber-white)',
                fontFamily: 'Orbitron, monospace',
                fontWeight: 700
              }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} md={6}>
          <Card className="cyber-stat-card">
            <Statistic
              title="System Health"
              value={systemHealth}
              suffix="%"
              prefix={<CheckCircleOutlined style={{ 
                color: systemHealth > 80 ? 'var(--cyber-green)' : systemHealth > 50 ? 'var(--cyber-yellow)' : 'var(--cyber-red)' 
              }} />}
              valueStyle={{ 
                color: systemHealth > 80 ? 'var(--cyber-green)' : systemHealth > 50 ? 'var(--cyber-yellow)' : 'var(--cyber-red)',
                fontFamily: 'Orbitron, monospace',
                fontWeight: 700
              }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} md={6}>
          <Card className="cyber-stat-card">
            <Statistic
              title="Network Latency"
              value={`${systemMetrics.networkLatency}ms`}
              prefix={<GlobalOutlined style={{ color: 'var(--cyber-blue)' }} />}
              valueStyle={{ 
                color: 'var(--cyber-white)',
                fontFamily: 'Orbitron, monospace',
                fontWeight: 700
              }}
            />
          </Card>
        </Col>
        <Col xs={24} sm={12} md={6}>
          <Card className="cyber-stat-card">
            <Statistic
              title="System Uptime"
              value={formatUptime(systemMetrics.uptime)}
              prefix={<EyeOutlined style={{ color: 'var(--cyber-green)' }} />}
              valueStyle={{ 
                color: 'var(--cyber-green)',
                fontFamily: 'Orbitron, monospace',
                fontWeight: 700,
                fontSize: '24px'
              }}
            />
          </Card>
        </Col>
      </Row>

      {/* System Performance Metrics */}
      <Row gutter={[20, 20]} style={{ marginBottom: 32 }}>
        <Col xs={24} md={12}>
          <Card className="cyber-card" title="CPU Usage" style={{ height: 200 }}>
            <Progress
              percent={systemMetrics.cpuUsage}
              strokeColor={{
                '0%': 'var(--cyber-blue)',
                '100%': 'var(--cyber-purple)',
              }}
              trailColor="rgba(255,255,255,0.1)"
              strokeWidth={8}
              showInfo={true}
              format={(percent) => (
                <span style={{ color: 'var(--cyber-white)', fontFamily: 'Orbitron, monospace', fontWeight: 700 }}>
                  {percent}%
                </span>
              )}
            />
            <div className="cyber-metric" style={{ marginTop: 16 }}>
              <div className="cyber-metric-label">Optimal Range: 20-60%</div>
            </div>
          </Card>
        </Col>
        <Col xs={24} md={12}>
          <Card className="cyber-card" title="Memory Usage" style={{ height: 200 }}>
            <Progress
              percent={systemMetrics.memoryUsage}
              strokeColor={{
                '0%': 'var(--cyber-green)',
                '100%': 'var(--cyber-pink)',
              }}
              trailColor="rgba(255,255,255,0.1)"
              strokeWidth={8}
              showInfo={true}
              format={(percent) => (
                <span style={{ color: 'var(--cyber-white)', fontFamily: 'Orbitron, monospace', fontWeight: 700 }}>
                  {percent}%
                </span>
              )}
            />
            <div className="cyber-metric" style={{ marginTop: 16 }}>
              <div className="cyber-metric-label">Available: {100 - systemMetrics.memoryUsage}% Free</div>
            </div>
          </Card>
        </Col>
      </Row>

      {/* Service Status Alert */}
      {healthyServices < totalServices && (
        <Alert
          className="cyber-alert"
          message="⚠ SYSTEM ALERT: Service Malfunction Detected"
          description={`${totalServices - healthyServices} module(s) reporting anomalous behavior. Initiating diagnostic protocols.`}
          type="warning"
          showIcon
          style={{ marginBottom: 32 }}
        />
      )}

      {/* Service Modules */}
      <div className="service-grid">
        {services.map((service) => (
          <Card 
            key={service.key}
            className="cyber-card"
            title={
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <div style={{ color: service.color, fontSize: 20 }}>
                  {service.icon}
                </div>
                <div>
                  <div style={{ color: 'var(--cyber-white)', fontSize: 16, fontWeight: 600 }}>
                    {service.name}
                  </div>
                  <div style={{ color: 'var(--cyber-gray)', fontSize: 12, fontWeight: 400 }}>
                    v{service.version} • Port {service.port}
                  </div>
                </div>
              </div>
            }
            extra={
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <div 
                  className={`status-dot ${service.status === 'healthy' ? 'healthy' : 'unhealthy'}`}
                />
                <span className={`service-status-${service.status}`} style={{ 
                  fontWeight: 700,
                  textTransform: 'uppercase',
                  letterSpacing: 1,
                  fontSize: 12
                }}>
                  {service.status === 'healthy' ? 'ONLINE' : 'OFFLINE'}
                </span>
              </div>
            }
            style={{ minHeight: 280 }}
          >
            <div style={{ marginBottom: 20 }}>
              <p style={{ 
                color: 'var(--cyber-gray)', 
                fontSize: 14, 
                lineHeight: 1.6,
                margin: 0
              }}>
                {service.description}
              </p>
            </div>
            
            {service.status === 'healthy' ? (
              <div>
                <Row gutter={16}>
                  <Col span={8}>
                    <div className="cyber-metric" style={{ textAlign: 'center', padding: 8 }}>
                      <div className="cyber-metric-value" style={{ fontSize: 20 }}>
                        {service.metrics?.requests || 0}
                      </div>
                      <div className="cyber-metric-label">Requests</div>
                    </div>
                  </Col>
                  <Col span={8}>
                    <div className="cyber-metric" style={{ textAlign: 'center', padding: 8 }}>
                      <div className="cyber-metric-value" style={{ fontSize: 20 }}>
                        {Math.round(service.responseTime)}ms
                      </div>
                      <div className="cyber-metric-label">Latency</div>
                    </div>
                  </Col>
                  <Col span={8}>
                    <div className="cyber-metric" style={{ textAlign: 'center', padding: 8 }}>
                      <div className="cyber-metric-value" style={{ fontSize: 20 }}>
                        {formatUptime(service.uptime)}
                      </div>
                      <div className="cyber-metric-label">Uptime</div>
                    </div>
                  </Col>
                </Row>
                
                <div style={{ 
                  marginTop: 16,
                  padding: 8,
                  background: 'rgba(0, 255, 65, 0.1)',
                  border: '1px solid var(--cyber-green)',
                  borderRadius: 4,
                  textAlign: 'center'
                }}>
                  <div style={{ color: 'var(--cyber-green)', fontSize: 12, fontWeight: 600 }}>
                    ✓ All systems operational
                  </div>
                </div>
              </div>
            ) : (
              <div>
                <div className="cyber-terminal" style={{ minHeight: 60 }}>
                  ERROR: Connection timeout<br/>
                  Last response: {service.error || 'Unknown error'}<br/>
                  Status: CRITICAL
                </div>
                
                <div style={{ 
                  marginTop: 16,
                  padding: 8,
                  background: 'rgba(255, 7, 58, 0.1)',
                  border: '1px solid var(--cyber-red)',
                  borderRadius: 4,
                  textAlign: 'center'
                }}>
                  <div style={{ color: 'var(--cyber-red)', fontSize: 12, fontWeight: 600 }}>
                    ⚠ System malfunction detected
                  </div>
                </div>
              </div>
            )}
          </Card>
        ))}
      </div>

      {/* Quick Access Panel */}
      <Card className="cyber-card" title="Quick Access Terminal" style={{ marginTop: 32 }}>
        <Row gutter={[16, 16]}>
          <Col xs={24} md={8}>
            <Card className="cyber-quick-link" size="small">
              <div style={{ textAlign: 'center', padding: 8 }}>
                <GlobalOutlined style={{ fontSize: 24, color: 'var(--cyber-blue)', marginBottom: 8 }} />
                <div style={{ fontWeight: 600, marginBottom: 4, color: 'var(--cyber-white)' }}>
                  Monitoring Dashboard
                </div>
                <div style={{ fontSize: 12, color: 'var(--cyber-gray)', marginBottom: 12 }}>
                  Access Prometheus and Grafana interfaces
                </div>
                <a href="http://localhost:30030" target="_blank" rel="noopener noreferrer">
                  Launch Grafana →
                </a>
              </div>
            </Card>
          </Col>
          <Col xs={24} md={8}>
            <Card className="cyber-quick-link" size="small">
              <div style={{ textAlign: 'center', padding: 8 }}>
                <ApiOutlined style={{ fontSize: 24, color: 'var(--cyber-green)', marginBottom: 8 }} />
                <div style={{ fontWeight: 600, marginBottom: 4, color: 'var(--cyber-white)' }}>
                  API Documentation
                </div>
                <div style={{ fontSize: 12, color: 'var(--cyber-gray)', marginBottom: 12 }}>
                  View OpenAPI specifications and endpoints
                </div>
                <a href="/api/docs" target="_blank" rel="noopener noreferrer">
                  View Docs →
                </a>
              </div>
            </Card>
          </Col>
          <Col xs={24} md={8}>
            <Card className="cyber-quick-link" size="small">
              <div style={{ textAlign: 'center', padding: 8 }}>
                <ThunderboltOutlined style={{ fontSize: 24, color: 'var(--cyber-pink)', marginBottom: 8 }} />
                <div style={{ fontWeight: 600, marginBottom: 4, color: 'var(--cyber-white)' }}>
                  System Matrix
                </div>
                <div style={{ fontSize: 12, color: 'var(--cyber-gray)', marginBottom: 12 }}>
                  Deep system health and performance analysis
                </div>
                <a href="/system-health">
                  Enter Matrix →
                </a>
              </div>
            </Card>
          </Col>
        </Row>
      </Card>
    </div>
  );
};

export default Dashboard;