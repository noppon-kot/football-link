class Tournament < ApplicationRecord
  belongs_to :organizer, class_name: "User"
  belongs_to :field

  has_many_attached :images, dependent: :purge_later

  # status: 0 = pending (รออนุมัติ), 1 = active (แสดงในหน้าค้นหา)
  enum status: { pending: 0, active: 1 }
  # plan: 0 = free (โพสต์รายละเอียด + ช่องทางติดต่ออย่างเดียว), 1 = pro (ใช้ระบบสมัครทีม/จัดสาย/ตารางแข่งขันได้)
  enum plan: { free: 0, pro: 1 }

  has_many :team_registrations, dependent: :destroy
  has_many :teams, through: :team_registrations
  has_many :tournament_divisions, dependent: :destroy

  has_many :tournament_staffs, dependent: :destroy
  has_many :staff_users, through: :tournament_staffs, source: :user

  accepts_nested_attributes_for :tournament_divisions, allow_destroy: true

  validates :title,
            :description,
            :location_name,
            :city,
            :province,
            :team_size,
            :contact_phone,
            :competition_date,
            :registration_open_on,
            :registration_close_on,
            presence: true

  validate :registration_dates_must_be_in_order

  validate :must_have_at_least_one_division

  validate :images_must_be_valid

  scope :active_for_search, -> {
    where(status: :active)
      .where("competition_date >= ?", Date.current)
  }

  before_validation :set_default_status, on: :create

  before_destroy :remember_team_ids_for_cleanup
  after_destroy :destroy_orphan_teams

  private

  def set_default_status
    self.status ||= :pending
  end

  def remember_team_ids_for_cleanup
    @team_ids_for_cleanup = team_registrations.pluck(:team_id).compact.uniq
  end

  def destroy_orphan_teams
    return if @team_ids_for_cleanup.blank?

    Team.where(id: @team_ids_for_cleanup).find_each do |team|
      next if team.team_registrations.exists?
      team.destroy
    end
  end

  def registration_dates_must_be_in_order
    return if registration_open_on.blank? || registration_close_on.blank?

    if registration_open_on > registration_close_on
      errors.add(:registration_open_on, "ต้องไม่ช้ากว่าวันปิดรับสมัคร")
      errors.add(:registration_close_on, "ต้องไม่เร็วกว่าวันเปิดรับสมัคร")
    end
  end

  def must_have_at_least_one_division
    # อนุญาตให้สร้าง Tournament เปล่า ๆ ได้ในเคสพิเศษ เช่น seed หรือสร้างตรงจาก console
    # ถ้าต้องการบังคับผ่านฟอร์ม จะมี tournament_divisions ติดมาด้วยอยู่แล้ว
    return if new_record? && tournament_divisions.empty?

    valid_divisions = tournament_divisions.reject(&:marked_for_destruction?).select { |d| d.name.present? }
    if valid_divisions.empty?
      errors.add(:tournament_divisions, "กรุณาเพิ่มอย่างน้อยหนึ่งรุ่นอายุของการแข่งขัน")
    end
  end

  def images_must_be_valid
    return unless images.attached?

    if images.attachments.size > 1
      errors.add(:images, "สามารถอัปโหลดได้ไม่เกิน 1 รูป")
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

  public

  def expired?
    competition_date.present? && competition_date < Date.current
  end
end
