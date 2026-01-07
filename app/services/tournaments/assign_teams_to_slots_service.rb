module Tournaments
  class AssignTeamsToSlotsService
    Result = Struct.new(:success?, :errors, keyword_init: true)

    def initialize(division:, slot_assignments: {})
      @division         = division
      @slot_assignments = slot_assignments || {}
    end

    def call
      cleaned_assignments = @slot_assignments.reject { |_, team_id| team_id.blank? }

      team_ids = cleaned_assignments.values.map(&:to_i)
      if team_ids.size != team_ids.uniq.size
        return Result.new(
          success?: false,
          errors: [
            "บันทึกไม่สำเร็จ: มีทีมที่ถูกเลือกซ้ำมากกว่าหนึ่งตำแหน่งในรุ่นนี้ กรุณาแก้ให้ทีมแต่ละทีมอยู่ได้เพียงตำแหน่งเดียว"
          ]
        )
      end

      ActiveRecord::Base.transaction do
        cleaned_assignments.each do |slot_label, team_id|
          team_id = team_id.to_i

          # Update all matches where this slot appears
          matches = @division.matches.where(
            "home_slot_label = :slot OR away_slot_label = :slot",
            slot: slot_label
          )

          matches.find_each do |match|
            if match.home_slot_label == slot_label
              match.home_team_id = team_id
            end
            if match.away_slot_label == slot_label
              match.away_team_id = team_id
            end
            match.save!
          end
        end
      end

      Result.new(success?: true, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, errors: Array(e.record&.errors&.full_messages).flatten)
    rescue StandardError => e
      Result.new(success?: false, errors: [e.message])
    end
  end
end
