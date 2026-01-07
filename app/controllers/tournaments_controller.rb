class TournamentsController < ApplicationController
  before_action :require_login, except: [:index, :show]
  before_action :set_tournament, only: [:show, :edit, :update, :approve, :teams, :fixture, :table, :assign_slot_teams, :update_points, :update_scores]
  before_action :require_edit_permission, only: [:edit, :update]
  def index
    result = ::Tournaments::IndexService.new(
      params: params,
      current_user: current_user,
      admin: admin?
    ).call

    @age_categories = result.age_categories
    @provinces      = result.provinces
    @tournaments    = result.tournaments
    @current_page   = result.current_page
    @total_pages    = result.total_pages
  end

  def approve
    result = ::Tournaments::ApproveService.new(
      tournament: @tournament,
      current_user: current_user,
      params: params
    ).call

    if result.success?
      redirect_to dashboard_path, notice: result.message
    else
      redirect_to dashboard_path, alert: result.message
    end
  end

  def show
    # @tournament is loaded in before_action :set_tournament
  end

  def teams
    # ใช้ @tournament จาก set_tournament และ logic เดิมใน view สำหรับทีมที่สนใจ / สมัคร
  end

  def fixture
    # ใช้ @tournament จาก set_tournament และ logic เดิมใน view สำหรับตารางแข่งขัน
  end

  def table
    # ใช้ @tournament จาก set_tournament และภายหลังจะเพิ่ม logic คำนวณตารางคะแนน
  end

  def generate_mock_schedule
    @tournament = Tournament.find(params[:id])

    result = ::Tournaments::GenerateMockScheduleHandler.new(
      tournament: @tournament,
      params: params,
      can_manage: can_manage_registrations?(@tournament)
    ).call

    target_path = teams_tournament_path(@tournament)

    if result.success?
      redirect_to target_path, notice: result.message
    else
      redirect_to target_path, alert: result.message
    end
  end

  def assign_slot_teams
    division = @tournament.tournament_divisions.find(params[:division_id])

    result = ::Tournaments::AssignTeamsToSlotsService.new(
      division: division,
      slot_assignments: params[:slot_assignments]
    ).call

    if result.success?
      redirect_to teams_tournament_path(@tournament), notice: "บันทึกการจัดทีมลงสายเรียบร้อยแล้ว"
    else
      redirect_to teams_tournament_path(@tournament), alert: result.errors.join(", ")
    end
  end

  def update_points
    division = @tournament.tournament_divisions.find(params[:division_id])

    unless can_manage_registrations?(@tournament)
      return redirect_to table_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    attrs = params.require(:division).permit(:points_win, :points_draw, :points_loss)

    if division.update(attrs)
      redirect_to table_tournament_path(@tournament), notice: "อัปเดตกติกาคะแนนเรียบร้อยแล้ว"
    else
      redirect_to table_tournament_path(@tournament), alert: division.errors.full_messages.join(", ")
    end
  end

  def update_scores
    unless can_manage_registrations?(@tournament)
      return redirect_to fixture_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    matches_params = params[:matches] || {}

    Match.transaction do
      matches_params.each do |match_id, attrs|
        match = Match.find_by(id: match_id)
        next unless match

        # attrs เป็น ActionController::Parameters อยู่แล้ว ใช้ permit ตรง ๆ ได้เลย
        permitted = attrs.permit(:home_score, :away_score)

        # อัปเดตเฉพาะคู่ที่เลือกสกอร์ครบทั้งสองฝั่ง
        next if permitted[:home_score].blank? && permitted[:away_score].blank?

        # ถ้ากรอกฝั่งใดฝั่งหนึ่งไม่ครบ ให้ข้าม ไม่บันทึกครึ่งเดียว
        next if permitted[:home_score].blank? || permitted[:away_score].blank?

        match.update!(permitted)
      end
    end

    redirect_to fixture_tournament_path(@tournament), notice: "บันทึกสกอร์เรียบร้อยแล้ว"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to fixture_tournament_path(@tournament), alert: e.record.errors.full_messages.join(", ")
  end

  def new
    @tournament = Tournament.new
    @tournament.tournament_divisions.build
  end

  def edit
  end

  def create
    attrs = tournament_params.dup
    # ถ้าไม่ได้ระบุ organizer มาจากฟอร์ม ให้ผูกกับผู้ใช้ปัจจุบัน
    attrs[:organizer_id] ||= current_user&.id

    service = ::Tournaments::CreateService.new(attrs)
    @tournament = service.tournament

    if service.call
      redirect_to @tournament, notice: I18n.t("tournaments.flash.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @tournament = Tournament.find(params[:id])
    permitted = tournament_params.to_h

    # ถ้าไม่ได้เลือกไฟล์รูปใหม่ อย่าไปแตะ images เดิม
    if permitted.key?("images")
      images_val = permitted["images"]
      if images_val.blank? || (images_val.is_a?(Array) && images_val.all?(&:blank?))
        permitted.delete("images")
      end
    end

    service = ::Tournaments::UpdateService.new(@tournament, permitted)

    if service.call
      redirect_to @tournament, notice: I18n.t("tournaments.flash.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_tournament
    @tournament = Tournament.includes(:field, :organizer, :teams, :team_registrations, :tournament_divisions).find(params[:id])
  end

  def require_edit_permission
    unless can_edit_tournament?(@tournament)
      redirect_to tournaments_path, alert: I18n.t("sessions.flash.login_required")
    end
  end

  def tournament_params
    params.require(:tournament).permit(
      :title,
      :description,
      :location_name,
      :city,
      :province,
      :line_id,
      :competition_date,
      :registration_open_on,
      :registration_close_on,
      :contact_phone,
      :team_size,
      :organizer_id,
      :field_id,
      images: [],
      tournament_divisions_attributes: [
        :id,
        :name,
        :entry_fee,
        :prize_amount,
        :match_format,
        :_destroy
      ]
    )
  end
end
