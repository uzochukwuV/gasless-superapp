'use client';

import { useEffect, useState } from 'react';

export interface NotificationMessage {
  id: string;
  type: 'success' | 'error' | 'info' | 'warning';
  title: string;
  message: string;
  duration?: number;
  action?: {
    label: string;
    onClick: () => void;
  };
}

interface NotificationProps {
  notification: NotificationMessage;
  onDismiss: (id: string) => void;
}

function NotificationItem({ notification, onDismiss }: NotificationProps) {
  useEffect(() => {
    if (notification.duration && notification.duration > 0) {
      const timer = setTimeout(() => onDismiss(notification.id), notification.duration);
      return () => clearTimeout(timer);
    }
  }, [notification, onDismiss]);

  const getIcon = () => {
    switch (notification.type) {
      case 'success':
        return '✓';
      case 'error':
        return '✕';
      case 'warning':
        return '⚠';
      case 'info':
        return 'ℹ';
      default:
        return '•';
    }
  };

  const getColors = () => {
    switch (notification.type) {
      case 'success':
        return 'bg-green-500/10 border-green-500/30 text-green-500';
      case 'error':
        return 'bg-red-500/10 border-red-500/30 text-red-500';
      case 'warning':
        return 'bg-yellow-500/10 border-yellow-500/30 text-yellow-500';
      case 'info':
        return 'bg-blue-500/10 border-blue-500/30 text-blue-500';
      default:
        return 'bg-black/30 border-border text-foreground';
    }
  };

  return (
    <div
      className={`rounded border p-4 mb-3 animate-slide-in-right ${getColors()}`}
      role="alert"
    >
      <div className="flex items-start gap-3">
        <span className="text-lg flex-shrink-0">{getIcon()}</span>
        <div className="flex-1">
          <h4 className="font-semibold text-sm">{notification.title}</h4>
          <p className="text-xs mt-1 opacity-90">{notification.message}</p>
        </div>
        <button
          onClick={() => onDismiss(notification.id)}
          className="flex-shrink-0 text-lg opacity-50 hover:opacity-100 transition-opacity"
        >
          ✕
        </button>
      </div>
      {notification.action && (
        <button
          onClick={notification.action.onClick}
          className="mt-3 text-xs font-semibold underline hover:opacity-80 transition-opacity"
        >
          {notification.action.label}
        </button>
      )}
    </div>
  );
}

interface NotificationContainerProps {
  notifications: NotificationMessage[];
  onDismiss: (id: string) => void;
}

export function NotificationContainer({
  notifications,
  onDismiss,
}: NotificationContainerProps) {
  return (
    <div className="fixed top-4 right-4 z-[100] max-w-sm w-full pointer-events-none">
      <div className="pointer-events-auto space-y-2">
        {notifications.map((notification) => (
          <NotificationItem
            key={notification.id}
            notification={notification}
            onDismiss={onDismiss}
          />
        ))}
      </div>
    </div>
  );
}
