class Team < ApplicationRecord
  has_many :team_registrations, dependent: :destroy
  has_many :tournaments, through: :team_registrations

  has_one_attached :logo

  validates :name, :contact_name, :contact_phone, presence: true
 
  def replace_logo!(attachable)
    transaction do
      logo.purge if logo.attached?
      logo.attach(attachable) if attachable.present?
    end
  end
end
