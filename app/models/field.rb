class Field < ApplicationRecord
  belongs_to :user

  # field_type: 0 = turf, 1 = grass
  enum field_type: { turf: 0, grass: 1 }
end
