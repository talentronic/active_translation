class Job < ApplicationRecord
  translates :title, :headline, :ad_html, into: %i[es fr], unless: -> { posted_status != "posted" }, cache: :title

  enum :posted_status, {
    draft: "draft",
    posted: "posted",
    expired: "expired",
  }
end
