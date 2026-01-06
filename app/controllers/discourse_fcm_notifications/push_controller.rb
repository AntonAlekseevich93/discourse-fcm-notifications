module ::DiscourseFcmNotifications
  class PushController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    layout false
    before_action :ensure_logged_in
    skip_before_action :preload_json

    def automatic_subscribe
      # 1. Если пришел запрос на удаление - удаляем и выходим
      if params[:token] == "REMOVE"
        DiscourseFcmNotifications::Pusher.unsubscribe(current_user)
        render json: { success: 'SUCCESS' }
        return
      end

      # 2. Попытка подписки (запись в базу)
      DiscourseFcmNotifications::Pusher.subscribe(current_user, params[:token])

      # 3. Попытка отправки пуша (игнорируем результат, так как там баг с таймером)
      DiscourseFcmNotifications::Pusher.confirm_subscribe(current_user)

      # 4. Проверка результата по факту наличия записи в базе
      # Перезагружаем юзера, чтобы увидеть свежие custom_fields
      current_user.reload 
      
      if current_user.custom_fields[DiscourseFcmNotifications::PLUGIN_NAME] == params[:token]
        render json: { success: 'SUCCESS' }
      else
        render json: { failed: 'FAILED', error: I18n.t("discourse_fcm_notifications.subscribe_error") }
      end
    end
    
    def subscribe
      if current_user.custom_fields[DiscourseFcmNotifications::PLUGIN_NAME] != params[:subscription]
        DiscourseFcmNotifications::Pusher.subscribe(current_user, params[:subscription])
        if DiscourseFcmNotifications::Pusher.confirm_subscribe(current_user)
          render json: success_json
        else
          render json: { failed: 'FAILED', error: I18n.t("discourse_fcm_notifications.subscribe_error") }
        end
      else
        render json: { failed: 'FAILED', error: I18n.t("discourse_fcm_notifications.the_same") }
      end
    end

    def unsubscribe
      DiscourseFcmNotifications::Pusher.unsubscribe(current_user)
      render json: success_json
    end

  end
end
