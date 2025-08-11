import React from 'react';
import { Layout, Typography, Tag } from 'antd';

const { Header: AntHeader } = Layout;
const { Title } = Typography;

const Header = () => {
  return (
    <AntHeader 
      className="app-header"
      style={{ 
        marginLeft: 200,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between'
      }}
    >
      <Title level={3} style={{ margin: 0, color: '#1890ff' }}>
        Microservices Platform
      </Title>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <Tag color="blue">Kubernetes</Tag>
        <Tag color="green">Monitoring</Tag>
        <Tag color="orange">SRE Demo</Tag>
      </div>
    </AntHeader>
  );
};

export default Header;