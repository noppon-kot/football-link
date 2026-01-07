module Tournaments
  class GenerateMockScheduleHandler
    Result = Struct.new(:success?, :message, keyword_init: true)

    def initialize(tournament:, params:, can_manage: false)
      @tournament = tournament
      @params     = params
      @can_manage = can_manage
    end

    def call
      return Result.new(success?: false, message: "คุณไม่มีสิทธิ์จัดตารางการแข่งขัน") unless @can_manage

      division = @tournament.tournament_divisions.find_by(id: @params[:division_id])
      group_count = @params[:group_count].to_i
      slots_per_group = @params[:slots_per_group].to_i

      return Result.new(success?: false, message: "ไม่พบรุ่นที่เลือก") if division.nil?

      if group_count <= 0 || slots_per_group <= 0
        return Result.new(success?: false, message: "กรุณากรอกจำนวนสายและจำนวนทีมต่อสายให้ถูกต้อง")
      end

      service = ::Tournaments::GenerateMockScheduleService.new(
        division: division,
        group_count: group_count,
        slots_per_group: slots_per_group,
        match_format: @params[:match_format]
      )

      if service.call
        Result.new(success?: true, message: "สร้างโครงตารางแข่งขันสำเร็จแล้ว")
      else
        Result.new(success?: false, message: "ไม่สามารถสร้างโครงตารางแข่งขันได้")
      end
    end
  end
end
