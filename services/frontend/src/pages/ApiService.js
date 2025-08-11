import React, { useState, useEffect } from 'react';
import { Card, Table, Button, Form, Input, message, Modal, Tag } from 'antd';
import { PlusOutlined, EditOutlined, DeleteOutlined, ReloadOutlined } from '@ant-design/icons';

const ApiService = () => {
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(false);
  const [modalVisible, setModalVisible] = useState(false);
  const [editingItem, setEditingItem] = useState(null);
  const [form] = Form.useForm();

  const endpoints = [
    { method: 'GET', path: '/api/items', description: 'Get all items' },
    { method: 'POST', path: '/api/items', description: 'Create new item' },
    { method: 'GET', path: '/api/items/:id', description: 'Get item by ID' },
    { method: 'PUT', path: '/api/items/:id', description: 'Update item' },
    { method: 'DELETE', path: '/api/items/:id', description: 'Delete item' },
    { method: 'GET', path: '/api/health', description: 'Health check' }
  ];

  const fetchItems = async () => {
    setLoading(true);
    try {
      const response = await fetch('/api/items');
      if (response.ok) {
        const data = await response.json();
        setItems(data);
      } else {
        message.error('Failed to fetch items');
      }
    } catch (error) {
      message.error('Service unavailable');
      // Mock data for demo
      setItems([
        { id: 1, name: 'Sample Item 1', description: 'Demo item', createdAt: new Date().toISOString() },
        { id: 2, name: 'Sample Item 2', description: 'Another demo item', createdAt: new Date().toISOString() }
      ]);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchItems();
  }, []);

  const handleSubmit = async (values) => {
    try {
      const url = editingItem ? `/api/items/${editingItem.id}` : '/api/items';
      const method = editingItem ? 'PUT' : 'POST';
      
      const response = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(values)
      });

      if (response.ok) {
        message.success(`Item ${editingItem ? 'updated' : 'created'} successfully`);
        setModalVisible(false);
        setEditingItem(null);
        form.resetFields();
        fetchItems();
      } else {
        message.error('Operation failed');
      }
    } catch (error) {
      message.error('Service unavailable');
    }
  };

  const handleDelete = async (id) => {
    try {
      const response = await fetch(`/api/items/${id}`, { method: 'DELETE' });
      if (response.ok) {
        message.success('Item deleted successfully');
        fetchItems();
      } else {
        message.error('Delete failed');
      }
    } catch (error) {
      message.error('Service unavailable');
    }
  };

  const showModal = (item = null) => {
    setEditingItem(item);
    setModalVisible(true);
    if (item) {
      form.setFieldsValue(item);
    } else {
      form.resetFields();
    }
  };

  const columns = [
    {
      title: 'ID',
      dataIndex: 'id',
      key: 'id',
      width: 80
    },
    {
      title: 'Name',
      dataIndex: 'name',
      key: 'name'
    },
    {
      title: 'Description',
      dataIndex: 'description',
      key: 'description'
    },
    {
      title: 'Created',
      dataIndex: 'createdAt',
      key: 'createdAt',
      render: (text) => new Date(text).toLocaleDateString()
    },
    {
      title: 'Actions',
      key: 'actions',
      render: (_, record) => (
        <div style={{ display: 'flex', gap: 8 }}>
          <Button
            icon={<EditOutlined />}
            onClick={() => showModal(record)}
            size="small"
          />
          <Button
            icon={<DeleteOutlined />}
            onClick={() => handleDelete(record.id)}
            danger
            size="small"
          />
        </div>
      )
    }
  ];

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
        <h1>API Service</h1>
        <div style={{ display: 'flex', gap: 8 }}>
          <Button icon={<ReloadOutlined />} onClick={fetchItems}>
            Refresh
          </Button>
          <Button type="primary" icon={<PlusOutlined />} onClick={() => showModal()}>
            Add Item
          </Button>
        </div>
      </div>

      <Card title="Service Endpoints" style={{ marginBottom: 24 }}>
        <div className="service-endpoints">
          {endpoints.map((endpoint, index) => (
            <div key={index} className="endpoint-item">
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <Tag 
                  className={`endpoint-method method-${endpoint.method.toLowerCase()}`}
                >
                  {endpoint.method}
                </Tag>
                <code>{endpoint.path}</code>
              </div>
              <span style={{ color: '#666' }}>{endpoint.description}</span>
            </div>
          ))}
        </div>
      </Card>

      <Card title="Items Management">
        <Table
          columns={columns}
          dataSource={items}
          rowKey="id"
          loading={loading}
          pagination={{ pageSize: 10 }}
        />
      </Card>

      <Modal
        title={editingItem ? 'Edit Item' : 'Create Item'}
        open={modalVisible}
        onCancel={() => {
          setModalVisible(false);
          setEditingItem(null);
          form.resetFields();
        }}
        onOk={() => form.submit()}
      >
        <Form form={form} onFinish={handleSubmit} layout="vertical">
          <Form.Item
            label="Name"
            name="name"
            rules={[{ required: true, message: 'Please enter item name' }]}
          >
            <Input />
          </Form.Item>
          <Form.Item
            label="Description"
            name="description"
            rules={[{ required: true, message: 'Please enter description' }]}
          >
            <Input.TextArea rows={3} />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  );
};

export default ApiService;