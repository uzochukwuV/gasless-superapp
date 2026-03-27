'use client';

import { useCallback, useState } from 'react';
import { NotificationMessage } from '@/components/common/Notification';

/**
 * Hook for managing notifications/toasts
 */
export function useNotification() {
  const [notifications, setNotifications] = useState<NotificationMessage[]>([]);

  /**
   * Show a notification
   */
  const show = useCallback(
    (
      type: NotificationMessage['type'],
      title: string,
      message: string,
      options?: {
        duration?: number;
        action?: {
          label: string;
          onClick: () => void;
        };
      }
    ) => {
      const id = `notification-${Date.now()}-${Math.random()}`;
      const notification: NotificationMessage = {
        id,
        type,
        title,
        message,
        duration: options?.duration ?? 5000,
        action: options?.action,
      };

      setNotifications((prev) => [...prev, notification]);

      return id;
    },
    []
  );

  /**
   * Show success notification
   */
  const success = useCallback(
    (title: string, message: string, options?: any) => {
      return show('success', title, message, options);
    },
    [show]
  );

  /**
   * Show error notification
   */
  const error = useCallback(
    (title: string, message: string, options?: any) => {
      return show('error', title, message, options);
    },
    [show]
  );

  /**
   * Show warning notification
   */
  const warning = useCallback(
    (title: string, message: string, options?: any) => {
      return show('warning', title, message, options);
    },
    [show]
  );

  /**
   * Show info notification
   */
  const info = useCallback(
    (title: string, message: string, options?: any) => {
      return show('info', title, message, options);
    },
    [show]
  );

  /**
   * Dismiss a notification
   */
  const dismiss = useCallback((id: string) => {
    setNotifications((prev) => prev.filter((n) => n.id !== id));
  }, []);

  /**
   * Dismiss all notifications
   */
  const dismissAll = useCallback(() => {
    setNotifications([]);
  }, []);

  return {
    notifications,
    show,
    success,
    error,
    warning,
    info,
    dismiss,
    dismissAll,
  };
}
