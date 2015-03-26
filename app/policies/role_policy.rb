class RolePolicy < ApplicationPolicy
  def index?
    current_system_user.is_admin? || current_system_user.role_in_app.has_permission?('Role', 'index')
  end 
end