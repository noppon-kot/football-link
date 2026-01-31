class Match < ApplicationRecord
  belongs_to :tournament_division
  belongs_to :group, optional: true
  belongs_to :home_team, class_name: "Team", optional: true
  belongs_to :away_team, class_name: "Team", optional: true

  has_many_attached :images, dependent: :purge_later

  has_many :match_lineups, dependent: :destroy
  has_many :match_events, dependent: :destroy

  enum status: { scheduled: 0, finished: 1 }
  enum stage: { group_stage: 0, knockout: 1 }

  validate :images_must_be_valid

  def winner
    return nil unless finished? && home_score.present? && away_score.present?
    return nil if home_score == away_score

    home_score > away_score ? home_team : away_team
  end

  def home_name
    home_team&.name.presence || format_slot_label(home_slot_label) || "-"
  end

  def away_name
    away_team&.name.presence || format_slot_label(away_slot_label) || "-"
  end

  def format_slot_label(label)
    return nil if label.blank?
    case label
    when /\AR(\d+)#(\d+)\z/
      rank = $1.to_i
      order = $2.to_i
      if order == 1
        "ที่#{rank} ดีที่สุด"
      else
        "ที่#{rank} ดีที่ #{order}"
      end
    when "BP1"
      "BP ที่ดีที่สุด"
    when /\ABP(\d+)\z/
      "BP ##{$1}"
    when /\A(\d+)([A-Z])\z/
      "ที่#{$1} สาย#{$2}"
    else
      label
    end
  end

  private

  def images_must_be_valid
    return unless images.attached?

    if images.attachments.size > 2
      errors.add(:images, "สามารถอัปโหลดได้ไม่เกิน 2 รูป")
    end

    images.each do |image|
      if image.blob.byte_size > 10.megabytes
        errors.add(:images, "ขนาดไฟล์ต้องไม่เกิน 10MB")
      end

      unless image.blob.content_type&.start_with?("image/")
        errors.add(:images, "ต้องเป็นไฟล์รูปภาพเท่านั้น")
      end
    end
  end
end
