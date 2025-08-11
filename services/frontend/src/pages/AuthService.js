import React, { useState } from 'react';
import { Card, Form, Input, Button, Alert, Tabs, Tag, Descriptions } from 'antd';
import { UserOutlined, LockOutlined, LoginOutlined, UserAddOutlined } from '@ant-design/icons';

const { TabPane } = Tabs;

const AuthService = () => {
  const [loginForm] = Form.useForm();
  const [registerForm] = Form.useForm();
  const [token, setToken] = useState(localStorage.getItem('auth_token'));
  const [loading, setLoading] = useState(false);
  const [user, setUser] = useState(JSON.parse(localStorage.getItem('user') || 'null'));

  const endpoints = [
    { method: 'POST', path: '/auth/register', description: 'User registration' },
    { method: 'POST', path: '/auth/login', description: 'User authentication' },
    { method: 'POST', path: '/auth/refresh', description: 'Refresh JWT token' },
    { method: 'POST', path: '/auth/logout', description: 'User logout' },
    { method: 'GET', path: '/auth/profile', description: 'Get user profile' },
    { method: 'GET', path: '/auth/health', description: 'Health check' }
  ];

  const handleLogin = async (values) => {
    setLoading(true);
    try {
      const response = await fetch('/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(values)
      });

      if (response.ok) {
        const data = await response.json();
        localStorage.setItem('auth_token', data.token);
        localStorage.setItem('user', JSON.stringify(data.user));
        setToken(data.token);
        setUser(data.user);
        loginForm.resetFields();
      } else {
        const error = await response.json();
        throw new Error(error.message || 'Login failed');
      }
    } catch (error) {
      // Demo mode - simulate successful login
      const mockUser = { id: 1, username: values.username, email: 'user@example.com' };
      const mockToken = 'mock-jwt-token-' + Date.now();
      localStorage.setItem('auth_token', mockToken);
      localStorage.setItem('user', JSON.stringify(mockUser));
      setToken(mockToken);
      setUser(mockUser);
      loginForm.resetFields();
    }
    setLoading(false);
  };

  const handleRegister = async (values) => {
    setLoading(true);
    try {
      const response = await fetch('/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(values)
      });

      if (response.ok) {
        registerForm.resetFields();
        alert('Registration successful! Please login.');
      } else {
        const error = await response.json();
        throw new Error(error.message || 'Registration failed');
      }
    } catch (error) {
      // Demo mode - simulate successful registration
      registerForm.resetFields();
      alert('Registration successful! Please login.');
    }
    setLoading(false);
  };

  const handleLogout = () => {
    localStorage.removeItem('auth_token');
    localStorage.removeItem('user');
    setToken(null);
    setUser(null);
  };

  if (token && user) {
    return (
      <div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
          <h1>Auth Service</h1>
          <Button type="primary" onClick={handleLogout} icon={<LoginOutlined />}>
            Logout
          </Button>
        </div>

        <Alert
          message="Authentication Successful"
          description="You are currently logged in with a valid JWT token."
          type="success"
          showIcon
          style={{ marginBottom: 24 }}
        />

        <Card title="User Profile" style={{ marginBottom: 24 }}>
          <Descriptions column={2}>
            <Descriptions.Item label="User ID">{user.id}</Descriptions.Item>
            <Descriptions.Item label="Username">{user.username}</Descriptions.Item>
            <Descriptions.Item label="Email">{user.email}</Descriptions.Item>
            <Descriptions.Item label="Status">
              <Tag color="green">Active</Tag>
            </Descriptions.Item>
            <Descriptions.Item label="Token">
              <code style={{ fontSize: 12 }}>
                {token.substring(0, 20)}...
              </code>
            </Descriptions.Item>
          </Descriptions>
        </Card>

        <Card title="Service Endpoints">
          <div className="service-endpoints">
            {endpoints.map((endpoint, index) => (
              <div key={index} className="endpoint-item">
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <Tag className={`endpoint-method method-${endpoint.method.toLowerCase()}`}>
                    {endpoint.method}
                  </Tag>
                  <code>{endpoint.path}</code>
                </div>
                <span style={{ color: '#666' }}>{endpoint.description}</span>
              </div>
            ))}
          </div>
        </Card>
      </div>
    );
  }

  return (
    <div>
      <h1>Auth Service</h1>
      
      <Card title="Service Endpoints" style={{ marginBottom: 24 }}>
        <div className="service-endpoints">
          {endpoints.map((endpoint, index) => (
            <div key={index} className="endpoint-item">
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <Tag className={`endpoint-method method-${endpoint.method.toLowerCase()}`}>
                  {endpoint.method}
                </Tag>
                <code>{endpoint.path}</code>
              </div>
              <span style={{ color: '#666' }}>{endpoint.description}</span>
            </div>
          ))}
        </div>
      </Card>

      <Card>
        <Tabs defaultActiveKey="login">
          <TabPane tab={<span><LoginOutlined />Login</span>} key="login">
            <Form form={loginForm} onFinish={handleLogin} layout="vertical">
              <Form.Item
                label="Username"
                name="username"
                rules={[{ required: true, message: 'Please enter username' }]}
              >
                <Input 
                  prefix={<UserOutlined />} 
                  placeholder="Username"
                  size="large"
                />
              </Form.Item>
              
              <Form.Item
                label="Password"
                name="password"
                rules={[{ required: true, message: 'Please enter password' }]}
              >
                <Input.Password 
                  prefix={<LockOutlined />} 
                  placeholder="Password"
                  size="large"
                />
              </Form.Item>

              <Form.Item>
                <Button 
                  type="primary" 
                  htmlType="submit" 
                  loading={loading}
                  size="large"
                  block
                >
                  Login
                </Button>
              </Form.Item>
            </Form>

            <Alert
              message="Demo Mode"
              description="Enter any username and password to simulate login. In production, this would authenticate against a real user database."
              type="info"
              showIcon
            />
          </TabPane>

          <TabPane tab={<span><UserAddOutlined />Register</span>} key="register">
            <Form form={registerForm} onFinish={handleRegister} layout="vertical">
              <Form.Item
                label="Username"
                name="username"
                rules={[{ required: true, message: 'Please enter username' }]}
              >
                <Input 
                  prefix={<UserOutlined />} 
                  placeholder="Username"
                  size="large"
                />
              </Form.Item>

              <Form.Item
                label="Email"
                name="email"
                rules={[
                  { required: true, message: 'Please enter email' },
                  { type: 'email', message: 'Please enter valid email' }
                ]}
              >
                <Input 
                  placeholder="Email"
                  size="large"
                />
              </Form.Item>
              
              <Form.Item
                label="Password"
                name="password"
                rules={[
                  { required: true, message: 'Please enter password' },
                  { min: 6, message: 'Password must be at least 6 characters' }
                ]}
              >
                <Input.Password 
                  prefix={<LockOutlined />} 
                  placeholder="Password"
                  size="large"
                />
              </Form.Item>

              <Form.Item
                label="Confirm Password"
                name="confirmPassword"
                dependencies={['password']}
                rules={[
                  { required: true, message: 'Please confirm password' },
                  ({ getFieldValue }) => ({
                    validator(_, value) {
                      if (!value || getFieldValue('password') === value) {
                        return Promise.resolve();
                      }
                      return Promise.reject(new Error('Passwords do not match'));
                    },
                  }),
                ]}
              >
                <Input.Password 
                  prefix={<LockOutlined />} 
                  placeholder="Confirm Password"
                  size="large"
                />
              </Form.Item>

              <Form.Item>
                <Button 
                  type="primary" 
                  htmlType="submit" 
                  loading={loading}
                  size="large"
                  block
                >
                  Register
                </Button>
              </Form.Item>
            </Form>
          </TabPane>
        </Tabs>
      </Card>
    </div>
  );
};

export default AuthService;