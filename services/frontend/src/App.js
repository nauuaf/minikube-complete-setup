import React from 'react';
import { Routes, Route } from 'react-router-dom';
import { Layout } from 'antd';
import Sidebar from './components/Sidebar';
import Header from './components/Header';
import Dashboard from './pages/Dashboard';
import ApiService from './pages/ApiService';
import AuthService from './pages/AuthService';
import ImageService from './pages/ImageService';
import SystemHealth from './pages/SystemHealth';
import './App.css';

const { Content } = Layout;

function App() {
  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sidebar />
      <Layout>
        <Header />
        <Content style={{ margin: '24px 16px', padding: 24, background: '#fff' }}>
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/api-service" element={<ApiService />} />
            <Route path="/auth-service" element={<AuthService />} />
            <Route path="/image-service" element={<ImageService />} />
            <Route path="/system-health" element={<SystemHealth />} />
          </Routes>
        </Content>
      </Layout>
    </Layout>
  );
}

export default App;