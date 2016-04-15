class SystemUsersController < ApplicationController
  layout proc {|controller| controller.request.xhr? ? false: "user_management" }
  respond_to :html, :js

  def new
    authorize :system_users, :new?
    @domains = policy_scope(Domain) 
    @errors = params[:errors] if params[:errors].present?
  end

  def create
    authorize :system_users, :create?

    begin
      username = params[:system_user][:username]
      domain = params[:system_user][:domain]
      auditing do
        SystemUser.create_by_username_and_domain!(username, domain)       
        flash[:success] = I18n.t("success.create_user", :username => (username + '@' + domain)) 
      end 
      SystemUserChangeLog.create_system_user(:current_user => current_system_user, :username => username, :domain => domain)
    rescue Rigi::InvalidUsername, Rigi::InvalidDomain => e
      Rails.logger.error "SystemUser[username=#{params[:system_user][:username]} , domain=#{params[:system_user][:domain]}] illegal format"
      @errors = e.error_message 
    rescue Rigi::RegisteredAccount, Rigi::AccountNotInLdap, Rigi::AccountNoCasino => e
      Rails.logger.error "SystemUser[username=#{params[:system_user][:username]} , domain=#{params[:system_user][:domain]}] create failed: #{e.error_message}"
      flash[:alert] = e.error_message
    end  
    redirect_to new_system_user_path({:errors => @errors}) 
  end

  def index
    @system_users = policy_scope(SystemUser.includes(:casinos))
    authorize :system_users, :index?
  end

  def show
    @system_user = SystemUser.find_by_id(params[:id])
    authorize @system_user, :show?
  end

  def edit_roles
    @system_user = SystemUser.find_by_id(params[:id])
    authorize @system_user, :edit_roles?
    apps = App.all
    roles = policy_scope(Role)

    @roles_by_apps = apps.map do |app|
      ros = roles.find_all { |role| role.app_id == app.id }
      {:app => app, :roles => ros }
    end

    @current_role_ids = @system_user.role_assignments.select(:role_id).map { |role_asm| role_asm.role_id }
    @current_app_ids = @system_user.app_system_users.select(:app_id).map { |app_asm| app_asm.app_id }
  end

  def update_roles
    @system_user = SystemUser.find_by_id(params[:id])
    authorize @system_user, :update_roles?

    roles = Role.find(role_ids_param)

    roles.each do |role|
      authorize role, :allow_to_assign?
    end

    prev_role_ids = @system_user.roles.pluck(:id)

    auditing(:audit_action => "edit_role") do
      @system_user.update_roles(role_ids_param)
      flash[:success] = I18n.t("success.edit_role", :user_name => @system_user.username)
    end

    bulk_create_change_log(@system_user, "edit_role", prev_role_ids, role_ids_param)
    redirect_to system_user_path(@system_user)
  end

  private
  def role_ids_param
    role_ids = App.all.map do |app|
      v = params[app.name.to_sym]
      v ? v.to_i : nil
    end
    
    role_ids.compact.uniq
  end

  def bulk_create_change_log(system_user, action, from_role_ids, to_role_ids)
    prev_roles = Role.find(from_role_ids).group_by {|role| role.app_id}
    next_roles = Role.find(to_role_ids).group_by {|role| role.app_id}
    apps = App.all

    apps.each do |app|
      prev_role = prev_roles[app.id] ? prev_roles[app.id].first : nil
      next_role = next_roles[app.id] ? next_roles[app.id].first : nil

      # skip when the original and current are identical
      next if prev_role && next_role && (prev_role.id == next_role.id)
      next if prev_role.nil? && next_role.nil?

      prev_role_name = prev_role ? prev_role.name : nil
      next_role_name = next_role ? next_role.name : nil

      create_change_log(system_user, action, app.name, prev_role_name, next_role_name)
    end
  end

  def create_change_log(system_user, action, app_name, from, to)
    system_user.active_casino_ids.each do |target_casino_id|
      cl = SystemUserChangeLog.new
      cl.target_username = system_user.username
      cl.target_domain = system_user.domain.name
      cl.action = action
      cl.action_by[:username] = current_system_user.username
      cl.action_by[:casino_ids] = current_system_user.active_casino_ids
      cl.action_by[:casino_id_names] = current_system_user.active_casino_id_names
      cl.change_detail[:app_name] = app_name
      cl.change_detail[:from] = from
      cl.change_detail[:to] = to
      cl.save!

      cl.target_casinos.create(:target_casino_id => target_casino_id, :target_casino_name => Casino.find(target_casino_id).name)
    end
  end

end
