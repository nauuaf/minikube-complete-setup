import React, { useState, useEffect } from 'react';
import { Layout } from 'antd';

const { Header: AntHeader } = Layout;

const Header = () => {
  const [systemTime, setSystemTime] = useState(new Date());
  const [systemStats, setSystemStats] = useState({
    online: true,
    monitoring: true,
    secure: true
  });

  useEffect(() => {
    const timer = setInterval(() => {
      setSystemTime(new Date());
    }, 1000);

    return () => clearInterval(timer);
  }, []);

  return (
    <AntHeader className="cyber-header" style={{ marginLeft: 200 }}>
      <div className="cyber-logo">
        NEXUS PLATFORM
      </div>
      
      <div style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
        <div style={{ 
          fontFamily: 'Orbitron, monospace', 
          fontSize: 14, 
          color: 'var(--cyber-blue)',
          letterSpacing: '1px'
        }}>
          {systemTime.toLocaleTimeString([], { 
            hour12: false,
            hour: '2-digit', 
            minute: '2-digit', 
            second: '2-digit' 
          })}
        </div>
        
        <div className="cyber-status-badges">
          <div className={`cyber-badge ${systemStats.online ? 'online' : ''}`}>
            ONLINE
          </div>
          <div className={`cyber-badge ${systemStats.monitoring ? 'monitoring' : ''}`}>
            MONITORING
          </div>
          <div className={`cyber-badge ${systemStats.secure ? 'secure' : ''}`}>
            SECURE
          </div>
        </div>
      </div>
    </AntHeader>
  );
};

export default Header;