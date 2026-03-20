module ActiveTranslation
  class Cache < ApplicationRecord
    self.table_name = :active_translation_cache

    validates :locale, presence: true
    validates :checksum, presence: true
  end
end
