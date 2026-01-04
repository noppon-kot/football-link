class User < ApplicationRecord
  # role: 0 = organizer, 1 = player, 2 = field_owner, 3 = sponsor
  enum role: { organizer: 0, player: 1, field_owner: 2, sponsor: 3 }

  has_many :organized_tournaments, class_name: "Tournament", foreign_key: :organizer_id, dependent: :nullify
  has_many :fields, dependent: :nullify
end
