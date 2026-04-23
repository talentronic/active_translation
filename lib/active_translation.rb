require "active_translation/version"
require "active_translation/engine"
require "active_translation/configuration"
require "active_translation/translatable"
require "active_translation/translation_job"
require "faraday"
require "googleauth"

module ActiveTranslation
  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def translate(text:, locale:, cache: true)
      text = text.to_s
      locale = locale.to_s

      if cache
        cached_translation = Cache.find_by(locale:, checksum: Digest::MD5.hexdigest(text))
        return cached_translation.translated_text if cached_translation
      end

      translated_text = GoogleTranslate.translate(target_language_code: locale, text:)

      Cache.add!(locale:, original_text: text, translated_text:) if cache

      translated_text
    end
  end
end
