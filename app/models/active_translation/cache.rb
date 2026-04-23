module ActiveTranslation
  class Cache < ApplicationRecord
    self.table_name = :active_translation_cache

    validates :locale, presence: true
    validates :checksum, presence: true

    class << self
      def add!(locale:, original_text:, translated_text:)
        find_or_create_by(
          checksum: Digest::MD5.hexdigest(original_text),
          locale:,
        ).update(translated_text:,)
      end

      def lookup(locale:, text:)
        text = text.to_s
        locale = locale.to_s

        find_by(
          checksum: Digest::MD5.hexdigest(text),
          locale:,
        )&.translated_text
      end
    end
  end
end
