import React, { useState, useEffect } from 'react';
import { Card, Row, Col, Statistic, Alert, Spin } from 'antd';
import {
  ApiOutlined,
  UserOutlined,
  PictureOutlined,
  CheckCircleOutlined,
  ExclamationCircleOutlined
} from '@ant-design/icons';

const Dashboard = () => {
  const [services, setServices] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const serviceEndpoints = [
    {
      name: 'API Service',
      key: 'api-service',
      url: '/api/health',
      port: 3000,
      icon: <ApiOutlined />,
      description: 'RESTful API service with CRUD operations'
    },
    {
      name: 'Auth Service',
      key: 'auth-service', 
      url: '/auth/health',
      port: 8080,
      icon: <UserOutlined />,
      description: 'JWT-based authentication service'
    },
    {
      name: 'Image Service',
      key: 'image-service',
      url: '/images/health',
      port: 5000,
      icon: <PictureOutlined />,
      description: 'Image upload and processing service'
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
          
          serviceStatuses.push({
            ...service,
            status: response.ok ? 'healthy' : 'unhealthy',
            responseTime: Date.now(),
            lastChecked: new Date().toISOString()
          });
        } catch (err) {
          serviceStatuses.push({
            ...service,
            status: 'unhealthy',
            error: err.message,
            lastChecked: new Date().toISOString()
          });
        }
      }

      setServices(serviceStatuses);
      setLoading(false);
    };

    checkServices();
    const interval = setInterval(checkServices, 30000); // Check every 30 seconds

    return () => clearInterval(interval);
  }, []);

  const healthyServices = services.filter(s => s.status === 'healthy').length;
  const totalServices = services.length;

  if (loading) {
    return (
      <div style={{ textAlign: 'center', padding: '50px' }}>
        <Spin size="large" />
        <p style={{ marginTop: 16 }}>Checking service health...</p>
      </div>
    );
  }

  return (
    <div>
      <h1>Platform Dashboard</h1>
      
      <Row gutter={16} style={{ marginBottom: 24 }}>
        <Col span={6}>
          <Card>
            <Statistic
              title="Total Services"
              value={totalServices}
              prefix={<ApiOutlined />}
            />
          </Card>
        </Col>
        <Col span={6}>
          <Card>
            <Statistic
              title="Healthy Services"
              value={healthyServices}
              prefix={<CheckCircleOutlined />}
              valueStyle={{ color: healthyServices === totalServices ? '#3f8600' : '#cf1322' }}
            />
          </Card>
        </Col>
        <Col span={6}>
          <Card>
            <Statistic
              title="System Health"
              value={`${Math.round((healthyServices / totalServices) * 100)}%`}
              prefix={<ExclamationCircleOutlined />}
              valueStyle={{ 
                color: healthyServices === totalServices ? '#3f8600' : '#cf1322' 
              }}
            />
          </Card>
        </Col>
        <Col span={6}>
          <Card>
            <Statistic
              title="Last Updated"
              value={new Date().toLocaleTimeString()}
            />
          </Card>
        </Col>
      </Row>

      {healthyServices < totalServices && (
        <Alert
          message="Service Health Warning"
          description="One or more services are not responding properly. Check individual service status below."
          type="warning"
          showIcon
          style={{ marginBottom: 24 }}
        />
      )}

      <Row gutter={16}>
        {services.map((service) => (
          <Col span={8} key={service.key}>
            <Card 
              className="service-card"
              title={
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  {service.icon}
                  {service.name}
                </div>
              }
              extra={
                <div className="service-status">
                  <div 
                    className={`status-dot ${
                      service.status === 'healthy' ? 'status-healthy' : 'status-unhealthy'
                    }`}
                  />
                  <span style={{ 
                    color: service.status === 'healthy' ? '#52c41a' : '#ff4d4f',
                    fontWeight: 'bold'
                  }}>
                    {service.status === 'healthy' ? 'Healthy' : 'Unhealthy'}
                  </span>
                </div>
              }
            >
              <p style={{ color: '#666', marginBottom: 16 }}>
                {service.description}
              </p>
              
              <div style={{ fontSize: 12, color: '#999' }}>
                <div>Port: {service.port}</div>
                <div>Last Checked: {new Date(service.lastChecked).toLocaleTimeString()}</div>
                {service.error && (
                  <div style={{ color: '#ff4d4f', marginTop: 4 }}>
                    Error: {service.error}
                  </div>
                )}
              </div>
            </Card>
          </Col>
        ))}
      </Row>

      <Card title="Quick Links" style={{ marginTop: 24 }}>
        <Row gutter={16}>
          <Col span={8}>
            <Card size="small" title="Monitoring">
              <p>Access Prometheus and Grafana dashboards</p>
              <a href="http://localhost:3001" target="_blank" rel="noopener noreferrer">
                Open Grafana →
              </a>
            </Card>
          </Col>
          <Col span={8}>
            <Card size="small" title="API Documentation">
              <p>View OpenAPI specifications for all services</p>
              <a href="/api/docs" target="_blank" rel="noopener noreferrer">
                View API Docs →
              </a>
            </Card>
          </Col>
          <Col span={8}>
            <Card size="small" title="System Metrics">
              <p>Real-time system health and performance metrics</p>
              <a href="/system-health">
                View System Health →
              </a>
            </Card>
          </Col>
        </Row>
      </Card>
    </div>
  );
};

export default Dashboard;