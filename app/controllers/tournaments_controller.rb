class TournamentsController < ApplicationController
  # ให้ทุกคนเข้า view ได้ทุกเมนูของทัวร์นาเมนต์ ยกเว้น action ที่แก้ไขข้อมูล
  before_action :require_login, except: [:index, :show, :teams, :fixture, :table]
  before_action :set_tournament, only: [:show, :edit, :update, :approve, :teams, :fixture, :table, :assign_slot_teams, :update_points, :update_scores, :destroy]
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

    unless can_manage_registrations?(@tournament)
      return redirect_to fixture_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    result = ::Tournaments::GenerateMockScheduleHandler.new(
      tournament: @tournament,
      params: params,
      can_manage: can_manage_registrations?(@tournament)
    ).call

    target_path = fixture_tournament_path(@tournament)

    if result.success?
      redirect_to target_path, notice: result.message
    else
      redirect_to target_path, alert: result.message
    end
  end

  def assign_slot_teams
    unless can_manage_registrations?(@tournament)
      return redirect_to teams_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

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
    unless can_manage_registrations?(@tournament)
      return redirect_to table_tournament_path(@tournament), alert: I18n.t("sessions.flash.login_required")
    end

    attrs = params.require(:division).permit(:points_win, :points_draw, :points_loss, :draw_mode, :points_pk_win, :points_pk_loss)

    divisions = @tournament.tournament_divisions
    errors = []

    ActiveRecord::Base.transaction do
      divisions.each do |division|
        unless division.update(attrs)
          errors = division.errors.full_messages
          raise ActiveRecord::Rollback
        end
      end
    end

    if errors.empty?
      redirect_to table_tournament_path(@tournament), notice: "อัปเดตกติกาคะแนนเรียบร้อยแล้ว (ใช้กับทุกรุ่น)"
    else
      redirect_to table_tournament_path(@tournament), alert: errors.join(", ")
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

        permitted = attrs.permit(:home_score, :away_score, :kickoff_at, :penalty_winner_side)

        update_attrs = {}

        # วันเวลาแข่ง
        update_attrs[:kickoff_at] = permitted[:kickoff_at] if permitted[:kickoff_at].present?

        # สกอร์: ต้องกรอกทั้งสองฝั่งถึงจะบันทึก
        home_score = permitted[:home_score]
        away_score = permitted[:away_score]
        scores_changed = false

        if home_score.present? || away_score.present?
          next if home_score.blank? || away_score.blank?

          update_attrs[:home_score] = home_score
          update_attrs[:away_score] = away_score
          scores_changed = true
        end

        # จุดโทษ: เชื่อค่าจาก dropdown โดยตรง
        winner_side_param = permitted[:penalty_winner_side]
        unless winner_side_param.nil?
          winner_side = winner_side_param.presence
          update_attrs[:decided_by_penalty]    = winner_side.present?
          update_attrs[:penalty_winner_side]   = winner_side
        end

        match.update!(update_attrs) if update_attrs.any?
      end
    end

    redirect_to fixture_tournament_path(@tournament), notice: "บันทึกสกอร์เรียบร้อยแล้ว"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to fixture_tournament_path(@tournament), alert: e.record.errors.full_messages.join(", ")
  end

  def new
    @tournament = Tournament.new
    if current_user
      @tournament.contact_phone ||= current_user.phone
      @tournament.line_id       ||= current_user.line_id
    end
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
      if current_user
        update_attrs = {}
        update_attrs[:phone]   = @tournament.contact_phone if @tournament.contact_phone.present?
        update_attrs[:line_id] = @tournament.line_id       if @tournament.line_id.present?
        current_user.update(update_attrs) if update_attrs.any?
      end
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

  def destroy
    unless admin?
      return redirect_to @tournament, alert: I18n.t("sessions.flash.login_required")
    end

    @tournament.destroy
    redirect_to tournaments_path, notice: "ลบรายการแข่งขันเรียบร้อยแล้ว"
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
