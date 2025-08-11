import React, { useState, useEffect } from 'react';
import { Card, Row, Col, Statistic, Progress, Alert, Table, Tag } from 'antd';
import {
  HeartOutlined,
  ClockCircleOutlined,
  DatabaseOutlined,
  CloudServerOutlined,
  WarningOutlined
} from '@ant-design/icons';

const SystemHealth = () => {
  const [metrics, setMetrics] = useState({});
  const [alerts, setAlerts] = useState([]);
  const [loading, setLoading] = useState(true);

  const fetchSystemMetrics = async () => {
    try {
      // In production, this would fetch from Prometheus or monitoring APIs
      const mockMetrics = {
        cpu: Math.floor(Math.random() * 30) + 15, // 15-45%
        memory: Math.floor(Math.random() * 40) + 30, // 30-70%
        disk: Math.floor(Math.random() * 20) + 20, // 20-40%
        network: Math.floor(Math.random() * 100) + 50, // 50-150 MB/s
        uptime: '7d 14h 23m',
        requestCount: Math.floor(Math.random() * 1000) + 5000,
        errorRate: (Math.random() * 2).toFixed(2), // 0-2%
        avgResponseTime: Math.floor(Math.random() * 200) + 50, // 50-250ms
        activeConnections: Math.floor(Math.random() * 100) + 200,
        pods: {
          running: 12,
          pending: 0,
          failed: 1,
          total: 13
        }
      };

      const mockAlerts = [
        {
          id: 1,
          severity: 'warning',
          message: 'High memory usage detected on api-service pod',
          timestamp: new Date(Date.now() - 300000).toISOString(), // 5 min ago
          status: 'active'
        },
        {
          id: 2,
          severity: 'info',
          message: 'New deployment completed successfully',
          timestamp: new Date(Date.now() - 900000).toISOString(), // 15 min ago
          status: 'resolved'
        },
        {
          id: 3,
          severity: 'critical',
          message: 'Pod image-service-7d4b8f9c5d-xyz failed to start',
          timestamp: new Date(Date.now() - 1800000).toISOString(), // 30 min ago
          status: 'active'
        }
      ];

      setMetrics(mockMetrics);
      setAlerts(mockAlerts);
    } catch (error) {
      console.error('Failed to fetch metrics:', error);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchSystemMetrics();
    const interval = setInterval(fetchSystemMetrics, 30000); // Refresh every 30 seconds
    return () => clearInterval(interval);
  }, []);

  const getHealthStatus = () => {
    const { cpu, memory, errorRate } = metrics;
    const cpuHigh = cpu > 80;
    const memoryHigh = memory > 80;
    const errorHigh = parseFloat(errorRate) > 5;

    if (cpuHigh || memoryHigh || errorHigh) {
      return { status: 'critical', color: '#ff4d4f', text: 'Critical' };
    } else if (cpu > 60 || memory > 60 || parseFloat(errorRate) > 2) {
      return { status: 'warning', color: '#faad14', text: 'Warning' };
    }
    return { status: 'healthy', color: '#52c41a', text: 'Healthy' };
  };

  const alertColumns = [
    {
      title: 'Severity',
      dataIndex: 'severity',
      key: 'severity',
      render: (severity) => {
        const colors = {
          critical: 'red',
          warning: 'orange',
          info: 'blue'
        };
        return <Tag color={colors[severity]}>{severity.toUpperCase()}</Tag>;
      }
    },
    {
      title: 'Message',
      dataIndex: 'message',
      key: 'message'
    },
    {
      title: 'Time',
      dataIndex: 'timestamp',
      key: 'timestamp',
      render: (timestamp) => {
        const date = new Date(timestamp);
        const now = new Date();
        const diffMs = now - date;
        const diffMins = Math.floor(diffMs / 60000);
        
        if (diffMins < 60) {
          return `${diffMins}m ago`;
        } else if (diffMins < 1440) {
          return `${Math.floor(diffMins / 60)}h ago`;
        } else {
          return date.toLocaleDateString();
        }
      }
    },
    {
      title: 'Status',
      dataIndex: 'status',
      key: 'status',
      render: (status) => (
        <Tag color={status === 'active' ? 'red' : 'green'}>
          {status.toUpperCase()}
        </Tag>
      )
    }
  ];

  const healthStatus = getHealthStatus();
  const activeAlerts = alerts.filter(alert => alert.status === 'active');

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
        <h1>System Health</h1>
        <Tag 
          color={healthStatus.color}
          style={{ fontSize: 14, padding: '4px 12px' }}
        >
          System Status: {healthStatus.text}
        </Tag>
      </div>

      {activeAlerts.length > 0 && (
        <Alert
          message={`${activeAlerts.length} Active Alert${activeAlerts.length > 1 ? 's' : ''}`}
          description="There are active alerts that require attention."
          type="warning"
          showIcon
          style={{ marginBottom: 24 }}
        />
      )}

      {/* Resource Metrics */}
      <Row gutter={16} style={{ marginBottom: 24 }}>
        <Col span={6}>
          <Card>
            <Statistic
              title="CPU Usage"
              value={metrics.cpu}
              suffix="%"
              prefix={<CloudServerOutlined />}
            />
            <Progress 
              percent={metrics.cpu} 
              strokeColor={metrics.cpu > 80 ? '#ff4d4f' : metrics.cpu > 60 ? '#faad14' : '#52c41a'}
              showInfo={false}
            />
          </Card>
        </Col>
        <Col span={6}>
          <Card>
            <Statistic
              title="Memory Usage"
              value={metrics.memory}
              suffix="%"
              prefix={<DatabaseOutlined />}
            />
            <Progress 
              percent={metrics.memory} 
              strokeColor={metrics.memory > 80 ? '#ff4d4f' : metrics.memory > 60 ? '#faad14' : '#52c41a'}
              showInfo={false}
            />
          </Card>
        </Col>
        <Col span={6}>
          <Card>
            <Statistic
              title="Disk Usage"
              value={metrics.disk}
              suffix="%"
              prefix={<DatabaseOutlined />}
            />
            <Progress 
              percent={metrics.disk} 
              strokeColor={metrics.disk > 80 ? '#ff4d4f' : metrics.disk > 60 ? '#faad14' : '#52c41a'}
              showInfo={false}
            />
          </Card>
        </Col>
        <Col span={6}>
          <Card>
            <Statistic
              title="Error Rate"
              value={metrics.errorRate}
              suffix="%"
              prefix={<WarningOutlined />}
              valueStyle={{
                color: parseFloat(metrics.errorRate) > 5 ? '#ff4d4f' : 
                       parseFloat(metrics.errorRate) > 2 ? '#faad14' : '#52c41a'
              }}
            />
          </Card>
        </Col>
      </Row>

      {/* Performance Metrics */}
      <Row gutter={16} style={{ marginBottom: 24 }}>
        <Col span={8}>
          <Card>
            <Statistic
              title="Total Requests"
              value={metrics.requestCount?.toLocaleString()}
              prefix={<HeartOutlined />}
            />
          </Card>
        </Col>
        <Col span={8}>
          <Card>
            <Statistic
              title="Avg Response Time"
              value={metrics.avgResponseTime}
              suffix="ms"
              prefix={<ClockCircleOutlined />}
            />
          </Card>
        </Col>
        <Col span={8}>
          <Card>
            <Statistic
              title="Active Connections"
              value={metrics.activeConnections}
            />
          </Card>
        </Col>
      </Row>

      {/* Pod Status */}
      <Row gutter={16} style={{ marginBottom: 24 }}>
        <Col span={12}>
          <Card title="Pod Status">
            <Row gutter={16}>
              <Col span={8}>
                <Statistic
                  title="Running"
                  value={metrics.pods?.running}
                  valueStyle={{ color: '#52c41a' }}
                />
              </Col>
              <Col span={8}>
                <Statistic
                  title="Pending"
                  value={metrics.pods?.pending}
                  valueStyle={{ color: '#faad14' }}
                />
              </Col>
              <Col span={8}>
                <Statistic
                  title="Failed"
                  value={metrics.pods?.failed}
                  valueStyle={{ color: '#ff4d4f' }}
                />
              </Col>
            </Row>
            <div style={{ marginTop: 16 }}>
              <Progress
                percent={Math.round((metrics.pods?.running / metrics.pods?.total) * 100)}
                format={() => `${metrics.pods?.running}/${metrics.pods?.total} pods healthy`}
                strokeColor="#52c41a"
              />
            </div>
          </Card>
        </Col>
        <Col span={12}>
          <Card title="System Uptime">
            <Statistic
              title="Uptime"
              value={metrics.uptime}
              prefix={<ClockCircleOutlined />}
              style={{ textAlign: 'center' }}
            />
            <div style={{ marginTop: 16, textAlign: 'center', color: '#666' }}>
              System has been running continuously
            </div>
          </Card>
        </Col>
      </Row>

      {/* Alerts Table */}
      <Card title="Recent Alerts">
        <Table
          columns={alertColumns}
          dataSource={alerts}
          rowKey="id"
          pagination={{ pageSize: 10 }}
          rowClassName={(record) => 
            record.status === 'active' ? 'alert-active' : 'alert-resolved'
          }
        />
      </Card>

      {/* Quick Links */}
      <Card title="Monitoring Links" style={{ marginTop: 24 }}>
        <Row gutter={16}>
          <Col span={8}>
            <Card size="small">
              <h4>Grafana Dashboards</h4>
              <p>View detailed metrics and custom dashboards</p>
              <a href="http://localhost:3001" target="_blank" rel="noopener noreferrer">
                Open Grafana →
              </a>
            </Card>
          </Col>
          <Col span={8}>
            <Card size="small">
              <h4>Prometheus Metrics</h4>
              <p>Raw metrics and query interface</p>
              <a href="http://localhost:9090" target="_blank" rel="noopener noreferrer">
                Open Prometheus →
              </a>
            </Card>
          </Col>
          <Col span={8}>
            <Card size="small">
              <h4>Kubernetes Dashboard</h4>
              <p>Native Kubernetes resource management</p>
              <Button type="link" style={{ padding: 0 }}>
                kubectl proxy required →
              </Button>
            </Card>
          </Col>
        </Row>
      </Card>

      <style jsx>{`
        .alert-active {
          background-color: #fff2f0;
        }
        .alert-resolved {
          opacity: 0.7;
        }
      `}</style>
    </div>
  );
};

export default SystemHealth;