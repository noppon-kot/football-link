module Tournaments
  class ApproveService
    Result = Struct.new(:success?, :message, keyword_init: true)

    def initialize(tournament:, current_user:, params: {})
      @tournament   = tournament
      @current_user = current_user
      @params       = params
    end

    def call
      return Result.new(success?: false, message: "คุณไม่มีสิทธิ์อนุมัติรายการแข่ง") unless admin?

      target_status = @params[:status]

      if target_status.present? && Tournament.statuses.key?(target_status)
        @tournament.update(status: target_status)
        message = target_status == "active" ? "อนุมัติรายการแข่งเรียบร้อยแล้ว" : "เปลี่ยนสถานะเป็นรออนุมัติเรียบร้อยแล้ว"
        Result.new(success?: true, message: message)
      elsif @tournament.pending?
        # fallback เดิม: ถ้าไม่ส่ง status มาและยัง pending ให้อนุมัติเป็น active
        @tournament.update(status: :active)
        Result.new(success?: true, message: "อนุมัติรายการแข่งเรียบร้อยแล้ว")
      else
        Result.new(success?: false, message: "ไม่สามารถเปลี่ยนสถานะรายการแข่งได้")
      end
    end

    private

    def admin?
      # ในระบบนี้ถือว่า user ที่มี role เป็น organizer คือผู้ดูแลที่มีสิทธิ์อนุมัติรายการแข่ง
      @current_user&.organizer?
    end
  end
end
