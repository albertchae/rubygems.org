# frozen_string_literal: true

module HcaptchaVerifier
  class << self
    VERIFY_ENDPOINT = "https://hcaptcha.com/siteverify"
    SIGN_IN_CAPTCHA_THRESHOLD = 4
    SIGN_UP_CAPTCHA_THRESHOLD = 2

    def should_verify_sign_in?(user_display_id)
      key = Rack::Attack::LOGIN_THROTTLE_PER_USER_KEY
      period = Rack::Attack::LOGIN_LIMIT_PERIOD

      keys = keys(key, period, user_display_id)
      should_verify(keys, SIGN_IN_CAPTCHA_THRESHOLD)
    end

    def should_verify_sign_up?(ip)
      key = Rack::Attack::SIGN_UP_THROTTLE_PER_IP_KEY
      period = Rack::Attack::SIGN_UP_LIMIT_PERIOD

      keys = keys(key, period, ip)
      should_verify(keys, SIGN_UP_CAPTCHA_THRESHOLD)
    end

    def call(client_response, remote_ip)
      return false unless client_response

      payload = {
        response: client_response,
        remoteip: remote_ip,
        secret: Rails.application.secrets.hcaptcha_secret,
        sitekey: Rails.application.secrets.hcaptcha_site_key
      }

      response = RestClient.post VERIFY_ENDPOINT,
        payload,
        :timeout        => 5,
        :open_timeout   => 5,
        "Content-Type"  => "application/x-www-form-urlencoded",
        "Accept" => "application/json"

      response_json = JSON.parse(response)

      Rails.logger.error("hCaptcha verification failed: #{response_json['error_codes'].join(';')}") if response_json["error_codes"]

      response_json["success"]
    end

    private

    def should_verify(keys, limit)
      keys.any? do |key|
        attempts = Rack::Attack.cache.store.read(key)
        attempts && attempts.to_i >= limit
      end
    end

    def keys(key, period, discriminator)
      time_counter      = (Time.now.to_i / period).to_i
      # counter may have incremented by 1 since the key was set, best to reset prev counter as well.
      # pre time counter/window key is applicable for +1 second after the counter has changed
      # see: https://github.com/kickstarter/rack-attack/pull/85
      prev_time_counter = time_counter - 1
      prefix            = Rack::Attack.cache.prefix
      ["#{prefix}:#{time_counter}:#{key}:#{discriminator}",
       "#{prefix}:#{prev_time_counter}:#{key}:#{discriminator}"]
    end
  end
end
