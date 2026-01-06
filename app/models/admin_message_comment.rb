class AdminMessageComment < ApplicationRecord
  belongs_to :admin_message
  belongs_to :user

  validates :body, presence: true
end
