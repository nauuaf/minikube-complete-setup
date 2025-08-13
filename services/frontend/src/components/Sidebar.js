import React from 'react';
import { Layout, Menu } from 'antd';
import { useNavigate, useLocation } from 'react-router-dom';
import {
  DashboardOutlined,
  ApiOutlined,
  UserOutlined,
  PictureOutlined,
  HeartOutlined,
  BarChartOutlined,
  SafetyCertificateOutlined,
  ThunderboltOutlined
} from '@ant-design/icons';

const { Sider } = Layout;

const Sidebar = () => {
  const navigate = useNavigate();
  const location = useLocation();

  const menuItems = [
    {
      key: '/',
      icon: <DashboardOutlined />,
      label: 'Command Center'
    },
    {
      key: '/api-service',
      icon: <ApiOutlined />,
      label: 'Neural API'
    },
    {
      key: '/auth-service',
      icon: <SafetyCertificateOutlined />,
      label: 'Security Core'
    },
    {
      key: '/image-service',
      icon: <PictureOutlined />,
      label: 'Vision Module'
    },
    {
      key: '/system-health',
      icon: <ThunderboltOutlined />,
      label: 'System Matrix'
    }
  ];

  const handleMenuClick = ({ key }) => {
    navigate(key);
  };

  return (
    <Sider
      width={200}
      className="cyber-sidebar"
      style={{
        overflow: 'auto',
        height: '100vh',
        position: 'fixed',
        left: 0,
        top: 0,
        bottom: 0,
      }}
    >
      <div className="cyber-sidebar-logo">
        NEXUS OS
      </div>
      
      <Menu
        theme="dark"
        mode="inline"
        selectedKeys={[location.pathname]}
        items={menuItems}
        onClick={handleMenuClick}
        style={{ background: 'transparent', border: 'none' }}
      />
      
      {/* System Status Indicator */}
      <div style={{
        position: 'absolute',
        bottom: 20,
        left: 16,
        right: 16,
        padding: 12,
        background: 'rgba(0, 0, 0, 0.3)',
        border: '1px solid var(--cyber-border)',
        borderRadius: 8,
        textAlign: 'center'
      }}>
        <div style={{
          fontSize: 10,
          color: 'var(--cyber-gray)',
          textTransform: 'uppercase',
          letterSpacing: 1,
          marginBottom: 4
        }}>
          System Status
        </div>
        <div style={{
          color: 'var(--cyber-green)',
          fontSize: 12,
          fontWeight: 600,
          textShadow: 'var(--cyber-glow-green)'
        }}>
          OPERATIONAL
        </div>
        <div style={{
          width: '100%',
          height: 2,
          background: 'var(--cyber-gradient-success)',
          borderRadius: 1,
          marginTop: 8,
          animation: 'pulse 2s infinite'
        }}></div>
      </div>
    </Sider>
  );
};

export default Sidebar;