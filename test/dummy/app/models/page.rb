class Page < ApplicationRecord
  translates :title, :heading, :content, manual: :subhead, into: :all, if: :published?, cache: [ :title, :heading ]
end
