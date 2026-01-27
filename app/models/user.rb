class User < ApplicationRecord
  # role: 0 = organizer, 1 = player, 2 = field_owner, 3 = sponsor
  enum :role, { organizer: 0, player: 1, field_owner: 2, sponsor: 3 }

  enum :package, { free: 0, pro: 1 }

  has_secure_password validations: false

  before_validation :normalize_username

  validates :username,
            presence: true,
            uniqueness: { case_sensitive: false },
            if: :local_account?
  validates :password,
            presence: true,
            confirmation: true,
            if: :local_account?,
            on: :create
  validates :security_question, presence: true, if: :local_account?
  validate :security_answer_presence_for_local_account

  has_many :organized_tournaments, class_name: "Tournament", foreign_key: :organizer_id, dependent: :nullify
  has_many :fields, dependent: :nullify
  has_many :managed_team_registrations, class_name: "TeamRegistration", foreign_key: :manager_user_id, dependent: :nullify

  has_many :team_registration_managers, dependent: :destroy
  has_many :managed_team_registrations_multi, through: :team_registration_managers, source: :team_registration

  has_many :tournament_staffs, dependent: :destroy
  has_many :staffed_tournaments, through: :tournament_staffs, source: :tournament

  def security_answer=(plain)
    self.security_answer_digest = plain.present? ? BCrypt::Password.create(plain) : nil
  end

  def security_answer_correct?(plain)
    return false if security_answer_digest.blank? || plain.blank?

    BCrypt::Password.new(security_answer_digest) == plain
  rescue BCrypt::Errors::InvalidHash
    false
  end

  def self.from_line_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.name = auth.info.name if auth.info.respond_to?(:name)
      user.email = auth.info.email.presence || "#{auth.uid}@line.me" if user.respond_to?(:email)
      user.phone = auth.info.phone if user.respond_to?(:phone) && auth.info.respond_to?(:phone)
    end
  end

  def local_account?
    provider.blank? && uid.blank?
  end

  private

  def normalize_username
    self.username = username.to_s.strip.downcase if username.present?
  end

  def security_answer_presence_for_local_account
    return unless local_account?
    return if security_answer_digest.present?

    errors.add(:base, "กรุณากรอกคำตอบสำหรับลืมรหัสผ่าน")
  end
end
