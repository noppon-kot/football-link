class AdminMessage < ApplicationRecord
  belongs_to :user
  belongs_to :tournament, optional: true

  has_many :admin_message_comments, dependent: :destroy

  enum status: { new_message: 0, in_progress: 1, done: 2 }

  validates :subject, presence: true
  validates :body, presence: true
end
