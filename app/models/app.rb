class App < ActiveRecord::Base
  has_many :roles
  has_many :app_system_users
  has_many :system_users, :through => :app_system_users

  def self.permissions(app_id)
    perm_hash ={}
    app = self.find_by_id(app_id)
    app.roles.each do |role|
      permissions = role.permissions
      permissions.each do |perm|
        if perm_hash.has_key?(perm.target.to_sym)
          perm_hash[perm.target.to_sym] << perm.name unless perm_hash[perm.target.to_sym].include? perm.name
        else
          perm_hash[perm.target.to_sym] = [perm.name]
        end
      end
    end
    perm_hash
  end
end
