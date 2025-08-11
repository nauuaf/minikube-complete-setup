import React, { useState, useEffect } from 'react';
import { Card, Upload, Button, Image, List, message, Tag, Progress } from 'antd';
import { 
  UploadOutlined, 
  PictureOutlined, 
  DeleteOutlined, 
  DownloadOutlined,
  ReloadOutlined
} from '@ant-design/icons';

const ImageService = () => {
  const [images, setImages] = useState([]);
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);

  const endpoints = [
    { method: 'POST', path: '/images/upload', description: 'Upload new image' },
    { method: 'GET', path: '/images', description: 'List all images' },
    { method: 'GET', path: '/images/:id', description: 'Get image by ID' },
    { method: 'DELETE', path: '/images/:id', description: 'Delete image' },
    { method: 'POST', path: '/images/:id/resize', description: 'Resize image' },
    { method: 'GET', path: '/images/health', description: 'Health check' }
  ];

  const fetchImages = async () => {
    setLoading(true);
    try {
      const response = await fetch('/images');
      if (response.ok) {
        const data = await response.json();
        setImages(data);
      } else {
        message.error('Failed to fetch images');
      }
    } catch (error) {
      message.error('Service unavailable');
      // Mock data for demo
      setImages([
        {
          id: 1,
          filename: 'sample-1.jpg',
          originalName: 'landscape.jpg',
          size: 1024000,
          mimeType: 'image/jpeg',
          uploadedAt: new Date().toISOString(),
          url: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMzAwIiBoZWlnaHQ9IjIwMCIgdmlld0JveD0iMCAwIDMwMCAyMDAiIGZpbGw9Im5vbmUiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+CjxyZWN0IHdpZHRoPSIzMDAiIGhlaWdodD0iMjAwIiBmaWxsPSIjZjBmMGYwIi8+Cjx0ZXh0IHg9IjE1MCIgeT0iMTAwIiBmaWxsPSIjY2NjIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LWZhbWlseT0iQXJpYWwiIGZvbnQtc2l6ZT0iMTQiPkRlbW8gSW1hZ2UgMTwvdGV4dD4KPC9zdmc+'
        },
        {
          id: 2,
          filename: 'sample-2.jpg',
          originalName: 'portrait.jpg',
          size: 2048000,
          mimeType: 'image/jpeg',
          uploadedAt: new Date().toISOString(),
          url: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMzAwIiBoZWlnaHQ9IjIwMCIgdmlld0JveD0iMCAwIDMwMCAyMDAiIGZpbGw9Im5vbmUiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+CjxyZWN0IHdpZHRoPSIzMDAiIGhlaWdodD0iMjAwIiBmaWxsPSIjZTZmN2ZmIi8+Cjx0ZXh0IHg9IjE1MCIgeT0iMTAwIiBmaWxsPSIjYWFhIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmb250LWZhbWlseT0iQXJpYWwiIGZvbnQtc2l6ZT0iMTQiPkRlbW8gSW1hZ2UgMjwvdGV4dD4KPC9zdmc+'
        }
      ]);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchImages();
  }, []);

  const handleUpload = async (file) => {
    setUploading(true);
    const formData = new FormData();
    formData.append('image', file);

    try {
      const response = await fetch('/images/upload', {
        method: 'POST',
        body: formData
      });

      if (response.ok) {
        const data = await response.json();
        message.success('Image uploaded successfully');
        fetchImages();
      } else {
        message.error('Upload failed');
      }
    } catch (error) {
      message.error('Service unavailable - simulating upload success');
      // Simulate successful upload
      const mockImage = {
        id: Date.now(),
        filename: `uploaded-${file.name}`,
        originalName: file.name,
        size: file.size,
        mimeType: file.type,
        uploadedAt: new Date().toISOString(),
        url: URL.createObjectURL(file)
      };
      setImages(prev => [mockImage, ...prev]);
      message.success('Image uploaded (demo mode)');
    }
    setUploading(false);
    return false; // Prevent default upload behavior
  };

  const handleDelete = async (id) => {
    try {
      const response = await fetch(`/images/${id}`, { method: 'DELETE' });
      if (response.ok) {
        message.success('Image deleted successfully');
        setImages(prev => prev.filter(img => img.id !== id));
      } else {
        message.error('Delete failed');
      }
    } catch (error) {
      message.error('Service unavailable');
      // Demo mode - remove from local state
      setImages(prev => prev.filter(img => img.id !== id));
      message.success('Image deleted (demo mode)');
    }
  };

  const formatFileSize = (bytes) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  const uploadProps = {
    beforeUpload: handleUpload,
    showUploadList: false,
    accept: 'image/*',
    multiple: true
  };

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
        <h1>Image Service</h1>
        <div style={{ display: 'flex', gap: 8 }}>
          <Button icon={<ReloadOutlined />} onClick={fetchImages}>
            Refresh
          </Button>
          <Upload {...uploadProps}>
            <Button type="primary" loading={uploading} icon={<UploadOutlined />}>
              Upload Images
            </Button>
          </Upload>
        </div>
      </div>

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

      {uploading && (
        <Card style={{ marginBottom: 24 }}>
          <Progress 
            percent={75} 
            status="active" 
            strokeColor="#1890ff"
            format={() => 'Uploading...'}
          />
        </Card>
      )}

      <Card title={`Uploaded Images (${images.length})`}>
        <List
          loading={loading}
          grid={{ gutter: 16, xs: 1, sm: 2, md: 3, lg: 4, xl: 4, xxl: 6 }}
          dataSource={images}
          renderItem={(image) => (
            <List.Item>
              <Card
                hoverable
                cover={
                  <div style={{ height: 200, overflow: 'hidden', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#f5f5f5' }}>
                    <Image
                      src={image.url}
                      alt={image.originalName}
                      style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'cover' }}
                      fallback="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMIAAADDCAYAAADQvc6UAAABRWlDQ1BJQ0MgUHJvZmlsZQAAKJFjYGASSSwoyGFhYGDIzSspCnJ3UoiIjFJgf8LAwSDCIMogwMCcmFxc4BgQ4ANUwgCjUcG3awyMIPqyLsis7PPOq3QdDFcvjV3jOD1boQVTPQrgSkktTgbSf4A4LbmgqISBgTEFyFYuLykAsTuAbJEioKOA7DkgdjqEvQHEToKwj4DVhAQ5A9k3gGyB5IxEoBmML4BsnSQk8XQkNtReEOBxcfXxUQg1Mjc0dyHgXNJBSWpFCYh2zi+oLMpMzyhRcASGUqqCZ16yno6CkYGRAQMDKMwhqj/fAIcloxgHQqxAjIHBEugw5sUIsSQpBobtQPdLciLEVJYzMPBHMDBsayhILEqEO4DxG0txmrERhM29nYGBddr//5/DGRjYNRkY/l7////39v///y4Dmn+LgeHANwDrkl1AuO+pmgAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAwqADAAQAAAABAAAAwwAAAAD9b/HnAAAHlklEQVR4Ae3dP3Ik1RUG8A+B4Hw8QB+Ah+BH8AA+ALDZ6AH8BpslnJu1pCqgZs4XqZlS7Xl+75x7703f7XvvLT+8a"
                    />
                  </div>
                }
                actions={[
                  <Button 
                    key="download" 
                    type="text" 
                    icon={<DownloadOutlined />}
                    onClick={() => {
                      const link = document.createElement('a');
                      link.href = image.url;
                      link.download = image.originalName;
                      document.body.appendChild(link);
                      link.click();
                      document.body.removeChild(link);
                    }}
                  />,
                  <Button 
                    key="delete" 
                    type="text" 
                    danger 
                    icon={<DeleteOutlined />}
                    onClick={() => handleDelete(image.id)}
                  />
                ]}
              >
                <Card.Meta
                  title={image.originalName}
                  description={
                    <div>
                      <div style={{ fontSize: 12, color: '#666' }}>
                        {formatFileSize(image.size)} • {image.mimeType}
                      </div>
                      <div style={{ fontSize: 11, color: '#999', marginTop: 4 }}>
                        {new Date(image.uploadedAt).toLocaleDateString()}
                      </div>
                    </div>
                  }
                />
              </Card>
            </List.Item>
          )}
        />
        
        {images.length === 0 && !loading && (
          <div style={{ textAlign: 'center', padding: 40, color: '#999' }}>
            <PictureOutlined style={{ fontSize: 48, marginBottom: 16 }} />
            <div>No images uploaded yet</div>
            <div>Upload some images to get started</div>
          </div>
        )}
      </Card>
    </div>
  );
};

export default ImageService;