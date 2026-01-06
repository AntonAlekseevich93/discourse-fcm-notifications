# frozen_string_literal: true

require "net/https"

module ::DiscourseFcmNotifications
  class Pusher
    
    # Метод push формирует сообщение из payload Discourse
    def self.push(user, payload)
      message = {
        title: I18n.t(
          "discourse_fcm_notifications.popup.#{Notification.types[payload[:notification_type]]}",
          site_title: SiteSetting.title,
          topic: payload[:topic_title],
          username: payload[:username]
        ),
        message: payload[:excerpt],
        url: "#{Discourse.base_url}/#{payload[:post_url]}"
      }
      self.send_notification(user, message)
    end

    # Метод для отправки тестового пуша при подписке
    def self.confirm_subscribe(user)
      message = {
        title: I18n.t(
          "discourse_fcm_notifications.confirm_title",
          site_title: SiteSetting.title,
        ),
        message: I18n.t("discourse_fcm_notifications.confirm_body"),
        url: "#{Discourse.base_url}"
      }
      self.send_notification(user, message)
    end

    # Сохранение токена в базу
    def self.subscribe(user, subscription)
      user.custom_fields[DiscourseFcmNotifications::PLUGIN_NAME] = subscription
      user.save_custom_fields(true)
    end

    # Удаление токена
    def self.unsubscribe(user)
      user.custom_fields.delete(DiscourseFcmNotifications::PLUGIN_NAME)
      user.save_custom_fields(true)
    end

    private

    # Основной метод отправки
    def self.send_notification(user, message_hash) 
      # ИЗМЕНЕНИЕ: Убрана проверка !self.already_sent?(user)
      # Теперь отправляем всегда, если есть юзер и сообщение
      if user and message_hash 
        Rails.logger.info "Sending a notification to #{user.username} about #{message_hash[:title]}"
        
        filename = "gcp_key.json"
        
        # Создаем файл ключа, если его нет
        if !File.exist?(filename) and SiteSetting.fcm_notifications_google_json
          File.open(filename, 'w') { |file| file.write(SiteSetting.fcm_notifications_google_json) }
        end
        
        # Если ключа все равно нет - ошибка
        unless File.exist?(filename)
           Rails.logger.error "Error: Missing google json for push notifications"
           return false
        end
        
        fcm = FCM.new(SiteSetting.fcm_notifications_api_key, filename, SiteSetting.fcm_notifications_project_id)

        token = user.custom_fields[DiscourseFcmNotifications::PLUGIN_NAME]
        
        # Если у юзера нет токена - ошибка
        unless token
             # Rails.logger.warn "User #{user.username} has no FCM token"
             return false
        end

        message = {
          'token': token,
          'data': {
            "linked_obj_type" => 'link',
            "linked_obj_data" => message_hash[:url],
          },
          'notification': {
            title: message_hash[:title],
            body: message_hash[:message],
          },
          'android': {
            "priority": "normal",
          },
          'apns': {
            headers:{
              "apns-priority":"5"
            },
            payload: {
              aps: {
                "category": "#{Time.zone.now.to_i}",
                "sound": "default",
                "interruption-level": "active"
              }
            },
          },
          'fcm_options': {
            "analytics_label": "Label"
          }
        }

        response = fcm.send_v1(message)
        
        if response[:response] == 'success'
          Rails.logger.info "Successfully sent push notification about #{message_hash[:title]} to token " + token.to_s 
          return true
        else
          # Логируем ошибки
          if response[:status_code] == 400
            txt = "ERROR: push notification was malformed. Tried to send notif about #{message_hash[:title]} to token " 
            txt += token.to_s + " and body response was: " + response[:body].to_s
            Rails.logger.error txt
          elsif response[:status_code] == 404
            Rails.logger.error "Possible error: push notification was sent to a token that is no longer valid. Unsubscribing user " + token.to_s
            self.unsubscribe user
          else 
            Rails.logger.error "ERROR: something was wrong with the push notification, code #{response[:status_code]}. Body: " + response[:body].to_s
          end
          return false
        end  
      end    
    end
  end
end
