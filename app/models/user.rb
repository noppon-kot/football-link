class User < ApplicationRecord
  # role: 0 = organizer, 1 = player, 2 = field_owner, 3 = sponsor
  enum role: { organizer: 0, player: 1, field_owner: 2, sponsor: 3 }

  has_many :organized_tournaments, class_name: "Tournament", foreign_key: :organizer_id, dependent: :nullify
  has_many :fields, dependent: :nullify

  def self.from_line_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.name = auth.info.name if auth.info.respond_to?(:name)
      user.email = auth.info.email.presence || "#{auth.uid}@line.me" if user.respond_to?(:email)
      user.phone = auth.info.phone if user.respond_to?(:phone) && auth.info.respond_to?(:phone)
    end
  end
end
