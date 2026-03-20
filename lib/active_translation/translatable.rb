module ActiveTranslation
  module Translatable
    extend ActiveSupport::Concern

    class_methods do
      def translates(*attributes, manual: [], into:, unless: nil, if: nil, cache: false)
        @translation_config ||= {}
        @translation_config[:attributes] = Array(attributes).map(&:to_s)
        @translation_config[:manual_attributes] = Array(manual).map(&:to_s)
        @translation_config[:locales] = into
        @translation_config[:unless] = binding.local_variable_get(:unless)
        @translation_config[:if] = binding.local_variable_get(:if)
        @translation_config[:cache] = cache

        has_many :translations, class_name: "ActiveTranslation::Translation", as: :translatable, dependent: :destroy

        delegate :translation_config, to: :class
        delegate :translatable_attribute_names, to: :class

        after_commit :translate_if_needed, on: [ :create, :update ]

        # Respond to calls for manual attribute retrieval (model.fr_attribute)
        # Respond to calls for manual attribute assignment (model.fr_attribute = "Bonjour")
        # Respond to calls such as fr_translation or de_translation
        # Respond to calls such as model.name(locale: :fr)
        define_method(:method_missing) do |method_name, *args, &block|
          # if the method name doesn't have an underscore with at least 1 character on both sides
          super(method_name, *args, &block) unless method_name.to_s.split("_", 2).reject(&:blank?).size == 2

          locale = method_name.to_s.split("_").first
          attribute = method_name.to_s.split("_").last

          # if something like "model.fr_title" is being called (no =)
          if translation_config[:manual_attributes].include? attribute
            translation = translations.find_by(locale: locale)
            return read_attribute(attribute) unless translation

            translation.translated_attributes[attribute].presence || read_attribute(attribute)
          # if something like "model.fr_title = 'Zut alors' is being called"
          elsif attribute.last == "=" && translation_config[:manual_attributes].include?(attribute.delete("="))
            attribute.delete!("=")
            translation = translations.find_or_initialize_by(locale: locale.to_s)
            attrs = translation.translated_attributes ? translation.translated_attributes : {}
            attrs[attribute] = args.first
            translation.translated_attributes = attrs
            translation.save!
          # if something like "model.fr_translation" is being called
          elsif attribute == "translation" || translation_config[:attributes].include?(attribute)
            translations.find_by(locale: locale)
          # if some method with an underscore that doesn't match anything above
          else
            super(method_name, *args, &block)
          end
        end

        # Override attribute methods so that they accept a locale argument (defaulting to current I18n locale)
        attributes.each do |attr|
          define_method(attr) do |locale: I18n.locale|
            if locale && translation = translations.find_by(locale: locale.to_s)
              translation.translated_attributes&.dig attr.to_s || super()
            else
              super()
            end
          end
        end

        # Override manual attribute methods so that they accept a locale argument (defaulting to current I18n locale)
        Array(manual).each do |attr|
          define_method("#{attr}") do |locale: I18n.locale|
            if locale && translation = translations.find_by(locale: locale.to_s)
              translation.translated_attributes[attr.to_s].presence || read_attribute(attr)
            else
              read_attribute(attr)
            end
          end
        end
      end

      def translatable_attribute_names
        translation_config[:attributes]
      end

      def translation_config
        @translation_config
      end
    end

    def fully_translated?(attribute_types = :auto)
      case attribute_types
      when :auto, :auto_only
        !translations_missing?
      when :manual, :manual_only
        !manual_translations_missing?
      when :all, :include_manual
        !translations_missing? && !manual_translations_missing?
      else
        raise ArgumentError, "acceptable arguments are [:auto, :auto_only, :manual, :manual_only, :all, :include_manual]"
      end
    end

    def manual_translations_missing?
      return false unless conditions_met?

      translatable_locales.each do |locale|
        translation_config[:manual_attributes].each do |attribute|
          next if read_attribute(attribute).blank?

          return true unless translation = translations.find_by(locale: locale)
          return true unless translation.translated_attributes.keys.include?(attribute)
        end
      end

      false
    end

    def outdated_translations
      translations.select { _1.outdated? }
    end

    def translatable_locales
      case translation_config[:locales]
      when Symbol
        if translation_config[:locales] == :all
          I18n.available_locales - [ I18n.default_locale ]
        else
          send(translation_config[:locales])
        end
      when Proc
        instance_exec(&translation_config[:locales])
      when Array
        translation_config[:locales]
      end
    end

    def translate_if_needed
      translations.delete_all and return unless conditions_met?

      return unless translatable_attributes_changed? || condition_checks_changed? || translations_outdated? || translations_missing?

      translatable_locales.each do |locale|
        translation = translations.find_or_create_by(locale: locale.to_s)

        if translation.new_record? || translation.outdated?
          TranslationJob.perform_later(self, locale.to_s, translation_checksum)
        end
      end
    end

    def translate!
      translatable_locales.each do |locale|
        TranslationJob.perform_later(self, locale.to_s, translation_checksum)
      end
    end

    def translate_now!(locales = translatable_locales)
      Array(locales).each do |locale|
        TranslationJob.perform_now(self, locale.to_s, translation_checksum)
      end
    end

    def translate_attribute(attribute, locale)
      return nil if send(attribute).nil?

      cached_translation = ActiveTranslation::Cache.find_by(
        checksum: text_checksum(send(attribute)),
        locale: locale,
      )

      translated_text = cached_translation&.translated_text || ActiveTranslation::GoogleTranslate.translate(target_language_code: locale, text: send(attribute))

      case translation_config[:cache]
      when TrueClass
        ActiveTranslation::Cache.find_or_create_by(
          checksum: text_checksum(send(attribute)),
          locale:,
        ).update(translated_text:,)
      when String, Symbol
        return unless attribute.to_s == translation_config[:cache].to_s

        ActiveTranslation::Cache.find_or_create_by(
          checksum: text_checksum(send(attribute)),
          locale:,
        ).update(translated_text:,)
      when Array
        return unless translation_config[:cache].map(&:to_s).include? attribute.to_s

        ActiveTranslation::Cache.find_or_create_by(
          checksum: text_checksum(send(attribute)),
          locale:,
        ).update(translated_text:,)
      end

      translated_text
    end

    def translation_cached?(attribute, locale)
      ActiveTranslation::Cache.find_by(
        checksum: text_checksum(send(attribute)),
        locale:,
      )
    end

    def translation_checksum
      values = translatable_attribute_names.map { |attr| read_attribute(attr).to_s }
      Digest::MD5.hexdigest(values.join)
    end

    # translations are "missing" if they are not manual, the translatable attribute isn't blank
    # and there's no translation for that attribute for all locales
    def translations_missing?
      return false unless conditions_met?

      translatable_locales.each do |locale|
        translatable_attribute_names.each do |attribute|
          next if read_attribute(attribute).blank?

          return true unless translation = translations.find_by(locale: locale)
          return true unless translation.translated_attributes.keys.include?(attribute)
        end
      end

      false
    end

    def translations_outdated?
      return false unless conditions_met?
      return true if translations.map(&:outdated?).any?

      false
    end

    private

    def condition_checks_changed?
      saved_changes.any? && conditions_exist? && conditions_met?
    end

    def conditions_exist?
      return true if translation_config[:if] || translation_config[:unless]

      false
    end

    # returns true if all conditions are met, or if there are no conditions
    def conditions_met?
      if_condition_met? && unless_condition_met?
    end

    def evaluate_condition(condition)
      case condition
      when Symbol
        send(condition)
      when Proc
        instance_exec(&condition)
      when nil
        true
      else
        false
      end
    end

    # returns true if condition is met or there is no condition
    def if_condition_met?
      return true unless translation_config[:if]

      evaluate_condition(translation_config[:if])
    end

    def text_checksum(text)
      Digest::MD5.hexdigest(text)
    end

    def translatable_attributes_changed?
      saved_changes.any? && saved_changes.keys.intersect?(translatable_attribute_names)
    end

    # returns true if condition is met or there is no condition
    def unless_condition_met?
      return true unless translation_config[:unless]

      !evaluate_condition(translation_config[:unless])
    end
  end
end
