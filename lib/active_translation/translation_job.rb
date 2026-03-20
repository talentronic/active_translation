module ActiveTranslation
  class TranslationJob < ActiveJob::Base
    queue_as :default

    def perform(object, locale, checksum)
      translated_data = {}

      object.translatable_attribute_names.each do |attribute|
        # source_text = object.read_attribute(attribute)
        # translated_data[attribute.to_s] = object.translate_text(source_text, locale)
        translated_data[attribute.to_s] = object.translate_attribute(attribute, locale)
      end

      translation = object.translations
        .find_or_initialize_by(
          locale: locale,
        )

      existing_data = translation.translated_attributes.present? ? translation.translated_attributes : {}

      merged_attributes = existing_data.merge(translated_data)

      translation.update!(
        translated_attributes: merged_attributes,
        source_checksum: checksum
      )
    end
  end
end
