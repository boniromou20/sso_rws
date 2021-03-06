class SystemUser < ActiveRecord::Base
  ACTIVE = 'active'
  INACTIVE = 'inactive'
  PENDING = 'pending'

  devise :registerable
  attr_accessible :id, :username, :status, :admin, :auth_source_id, :domain_id, :verified
  has_many :role_assignments, :as => :user, :dependent => :destroy
  has_many :roles, :through => :role_assignments
  has_many :app_system_users
  has_many :apps, :through => :app_system_users
  belongs_to :domain
  has_many :casinos_system_users
  has_many :casinos, :through => :casinos_system_users
  has_many :active_casinos_system_users, :class_name => 'CasinosSystemUser', :conditions => {casinos_system_users: {status: true}}
  has_many :active_casinos, :through => :active_casinos_system_users, :class_name => 'Casino', :source => :casino
  validate :username, :presence => true, :message => I18n.t("alert.invalid_username")

  scope :with_active_casino, -> { joins(:casinos_system_users).where("casinos_system_users.status = ?", true).select("DISTINCT(system_users.id), system_users.*") }

  def timezone
    @timezone ||= TZInfo::Timezone.get(timezone_name)
  end

  def timezone_name
    @timezone_name ||= Rails.cache.fetch(id).try(:[], :timezone) || DEFAULT_TIMEZONE
  end

  def username_with_domain
    "#{self.username}@#{self.domain.name}"
  end

  def active_casino_ids
    self.active_casinos.map{|casino| casino.id}
  end

  def all_casino_ids
    self.casinos.map{|casino| casino.id}
  end

  def active_casino_id_names
    rtn = []
    self.active_casinos.each do |casino|
      rtn.push({id: casino.id, name: casino.name})
    end
    rtn
  end

  def is_admin?
    admin
  end

  def has_admin_casino?
    active_casino_ids.include?(ADMIN_CASINO_ID)
  end

  def licensee
    casino = self.active_casinos.first
    casino.licensee if casino
  end

  def self.register!(username, domain, casino_ids)
    transaction do
      domain = Domain.where(:name => domain).first
      system_user = create!(:username => username, :domain_id => domain.id, :status => ACTIVE)
      system_user.update_casinos(casino_ids) if casino_ids
    end
  end

  def self.register_without_check!(username, domain)
    domain = Domain.where(:name => domain).first
    create!(:username => username, :domain_id => domain.id, :status => PENDING, :verified => false)
  end

  alias_method "is_root?", "is_admin?"

  def activated?
    self.status == ACTIVE
  end

  def inactived?
    self.status == INACTIVE
  end

  def pending?
    self.status == PENDING
  end

  def self.inactived
    where(status: INACTIVE)
  end

  def update_roles(role_ids)
    existing_roles = self.role_assignments.map { |role_assignment| role_assignment.role_id }
    diff_role_ids = self.class.diff(existing_roles, role_ids)

    transaction do
      diff_role_ids.each do |role_id|
        if existing_roles.include?(role_id)
          revoke_role(role_id)
        elsif
          assign_role(role_id)
        end
      end
    end

    refresh_permission_cache
  end

  def role_in_app(app_name=nil)
    app = App.find_by_name(app_name || APP_NAME)

    self.roles.includes(:app, :role_permissions => :permission).each do |role|
      if role.app.id == app.id
        return role
      end
    end

    nil
  end

  # determine if the user has permission on a particular action (in this app by default)
  def has_permission?(target, action, app_name=APP_NAME)
    role = role_in_app(app_name)
    role && role.has_permission?(target, action)
  end

  def cache_info(app_name)
    cache_profile
    cache_permissions(app_name) unless is_admin?
  end

  def update_casinos(casino_ids)
    CasinosSystemUser.update_casinos_by_system_user(id, casino_ids)
  end

  def update_user_profile(casino_ids)
    update_casinos(casino_ids)
    save!
  end

  def update_status(status)
    self.status = status
    save!
  end

  def update_verified(verified)
    self.verified = verified
    save!
  end

  def refresh_permission_cache
    all_app_ids = App.all
    assigned_app_ids = self.apps(true).map { |app| app.id }

    all_app_ids.each do |existing_app|
      if assigned_app_ids.include?(existing_app.id)
        cache_permissions(existing_app.name)
      else
        cache_revoke_permissions(existing_app.name)
      end
    end
  end

  def self.sync_user_info
    Rails.logger.info "Begin to Sync system user info"
    system_users = SystemUser.all

    if system_users.present?
      system_users.each do |system_user|
        begin
          domain = system_user.domain
          auth_source_detail = domain.auth_source_detail
          if auth_source_detail.blank?
            Rails.logger.info "**************************"
            Rails.logger.info "Cannot sync user [#{system_user.username}@#{domain.name}], auth_source_detail is null"
            next
          end
          user_type = domain.user_type || 'Ldap'
          profile = user_type.constantize.new.retrieve_user_profile(auth_source_detail, "#{system_user.username}@#{domain.name}", domain.get_casino_ids)
          if profile.present?
            if system_user.status != profile[:status]
              system_user.status = profile[:status]
              system_user.save!
            end
            system_user.update_casinos(profile[:casino_ids])
            system_user.cache_profile
          end
        rescue StandardError => e
          Rails.logger.error "Sync system user [#{system_user.inspect}] Exception: #{e.message}"
          Rails.logger.error "#{e.backtrace.inspect}"
          next
        end
      end
    end
    Rails.logger.info "End to Sync system user info"
  end

  def cache_profile
    cache_key = "#{self.id}"
    casinos = self.active_casinos
    casino_ids = casinos.map(&:id)
    licensee = casinos.first.licensee if casinos.present?
    properties = Property.where(:casino_id => casino_ids).pluck(:id)
    cache_hash = {
      :status => self.status,
      :admin => self.admin,
      :username_with_domain => "#{self.username}@#{self.domain.name}",
      :casinos => casino_ids,
      :licensee => licensee.try(:id),
      :properties => properties,
      :timezone => licensee.try(:timezone) || DEFAULT_TIMEZONE
    }
    Rails.cache.write(cache_key, cache_hash)
  end

  def self.get_export_system_users
    SystemUser.includes(:roles).joins(:domain).select("system_users.*, domains.name as domain_name").order("system_users.updated_at desc")
  end

  def insert_login_history(app_name, session_token)
    app = App.find_by_name(app_name || APP_NAME)
    params = {}
    params[:system_user_id] = self.id
    params[:domain_id] = self.domain_id
    params[:app_id] = app.id
    params[:session_token] = session_token
    params[:detail] = {:casino_ids => self.active_casino_ids, :casino_id_names => self.active_casino_id_names}
    LoginHistory.insert(params)
  end

  def self.find_by_username_with_domain(username_with_domain)
    username, domain = username_with_domain.split('@', 2)
    return nil if username.nil? || domain.nil?
    SystemUser.includes(:domain).where('system_users.username = ? and domains.name = ?', username, domain).first
  end

  def self.validate_username!(username)
    raise Rigi::InvalidUsername.new(I18n.t("alert.invalid_username")) if username.blank? || username.index(/\s/)
  end

  def backfill_change_logs
    return if verified
    change_logs = find_change_logs_by_action(['edit_role', 'create', 'inactive'])
    change_logs.each do |change_log|
      change_log.backfill(self)
    end
  end

  def find_change_logs_by_action(actions)
    SystemUserChangeLog.where(target_username: username, target_domain: domain.name).by_action(actions)
  end

  def authorize!(app_name, casino_id, permission)
    app = App.find_by_name(app_name)
    raise Rigi::InvalidAuthorize.new('Authorize failed, Casino not match') unless active_casino_ids.include?(casino_id.to_i)
    return if self.is_admin?
    role_ids = self.roles.where(app_id: app.id).map(&:id)
    permission = Permission.joins(:roles).where(roles: {id: role_ids}, app_id: app.id, target: permission[0], action: permission[1])
    raise Rigi::InvalidAuthorize.new('Authorize failed, Permission denied') if permission.blank?
  end

  private
  # a = [2, 4, 6, 8]
  # b = [1, 2, 3, 4]
  #  => [6, 8, 1, 3]
  def self.diff(x,y)
    o = x
    x = x.reject{|a| if y.include?(a); a end }
    y = y.reject{|a| if o.include?(a); a end }
    x | y
  end

  def assign_role(role_id)
    Rails.logger.info "Grant role (id=#{role_id}) for #{self.class.name} (id=#{self.id})"
    self.role_assignments.create({:role_id => role_id})
    role = Role.find_by_id(role_id)
    add_app_assignment(role.app_id)
  end

  def revoke_role(role_id)
    Rails.logger.info "Revoke role (id=#{role_id}) for #{self.class.name} (id=#{self.id})"
    self.role_assignments.find_by_role_id(role_id).destroy
    role = Role.find_by_id(role_id)
    remove_app_assignment(role.app_id)
  end

  def add_app_assignment(app_id)
    Rails.logger.info "Assign App (id=#{app_id}) for #{self.class.name} (id=#{self.id})"
    self.app_system_users.create({:app_id => app_id})
  end

  def remove_app_assignment(app_id)
    Rails.logger.info "Remove App (id=#{app_id}) for #{self.class.name} (id=#{self.id})"
    self.app_system_users.find_by_app_id(app_id).destroy
  end

  def cache_revoke_permissions(app_name)
    cache_key = "#{app_name}:permissions:#{self.id}"
    Rails.cache.delete(cache_key)
  end

  def cache_permissions(app_name)
    cache_key = "#{app_name}:permissions:#{self.id}"
    role = role_in_app(app_name)
    return unless role
    permissions = role.permissions
    targets = permissions.map{|x| x.target}.uniq
    perm_hash = {}
    value_hash = {}

    targets.each do |t|
      actions = []

      permissions.each do |perm|
        if perm.target == t
          actions << perm.action
          role_permission_value = role.get_permission_value(t, perm.action)
          if role_permission_value
            value_hash[t.to_sym] ||= {}
            value_hash[t.to_sym][perm.action.to_sym] = role_permission_value
          end
        end
      end

      perm_hash[t.to_sym] = actions
    end

    Rails.cache.write(cache_key, {:permissions => {:role => role.name, :permissions => perm_hash, :values => value_hash}})
  end
end
