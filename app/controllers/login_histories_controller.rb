class LoginHistoriesController < ApplicationController
	layout proc {|controller| controller.request.xhr? ? false: "user_management" }
  respond_to :html, :js
  include FormattedTimeHelper

  def index
    authorize :login_history, :list?

    if params[:commit].present?
      handle_search_with_result
    else
      @default_start_time = format_date(Time.now - (SEARCH_RANGE_FOR_LOGIN_HISTORY - 1).days)
      @default_end_time = format_date(Time.now)
      @apps = App.all
    end
  end

  private

  def handle_search_with_result
    @start_time_text = params[:start_time]
    @end_time_text = params[:end_time]
    @username = params[:username]
    @app_id = params[:app_id] unless params[:app_id].blank? || params[:app_id] == "all"
    start_time, end_time, remark = format_time_range(params[:start_time], params[:end_time], SEARCH_RANGE_FOR_LOGIN_HISTORY)
    if start_time.nil? && end_time.nil?
      @search_error = I18n.t("login_history.search_range_error", :config_value => SEARCH_RANGE_FOR_LOGIN_HISTORY)
    else
      if remark
        @search_time_range_remark = I18n.t("login_history.search_range_remark", :config_value => SEARCH_RANGE_FOR_LOGIN_HISTORY)
        @start_time_text = format_date(start_time)
        @end_time_text = format_date(end_time - 1.days)
      end
      if @username.present?
	      system_user = SystemUser.find_by_username_with_domain(@username)
	      if system_user.present?
		      system_user_id = system_user.id
		      domain_id = system_user.domain_id
        else
          @search_error = I18n.t("login_history.search_system_user_error")
		    end
	    end

	    if @search_error.blank?
		    @login_histories = policy_scope(LoginHistory.search_query(system_user_id, domain_id, @app_id, start_time, end_time)).as_json(:include => ['system_user', 'domain', 'app'])
      end
    end
  end
end
