require 'net/ldap'
require 'devise/strategies/authenticatable'
#require 'authentication/ldap'

module Devise
  module Strategies
    class LdapAuthenticatable < Authenticatable
      def valid?
        username || password
      end

      def authenticate!
        auth_source = AuthSource.get_default_auth_source 
        sys_usr = SystemUser.get_by_username_and_domain(username, auth_source.domain)
        unless sys_usr
          fail!("alert.invalid_login")
          Rails.logger.info "SystemUser[username=#{username}][domain=#{auth_source.domain}] Login failed. Not a registered account"
          return
        end
        unless sys_usr.activated?
          fail!("alert.inactive_account")
          Rails.logger.info "SystemUser[username=#{username}][domain=#{auth_source.domain}] Login failed. Inactive_account"
          return
        end
 	unless sys_usr.is_admin?
          unless sys_usr.role_in_app
	    fail!("alert.account_no_role")
            Rails.logger.info "SystemUser[username=#{username}][domain=#{auth_source.domain}] Login failed. No role assigned"
            return
          end
        end
#        auth_source = AuthSource.find_by_id(sys_usr.auth_source_id)
        auth_source = auth_source.becomes(auth_source.auth_type.constantize)
        if auth_source.authenticate(sys_usr.login, password)
          success!(sys_usr)
          return
        else
          Rails.logger.info "SystemUser[username=#{username}][domain=#{auth_source.domain}] Login failed. Authentication failed"
          fail!("alert.invalid_login")
          return
        end
      end

      def username
	if params[:system_user]
	  return params[:system_user][:username]
        end
	return nil
      end

      def password
	if params[:system_user]
          return params[:system_user][:password]
        end
        return nil
      end
    end
  end
end

Warden::Strategies.add(:ldap_authenticatable, Devise::Strategies::LdapAuthenticatable)
#Devise.add_module :ldap_authenticatable, :strategy => true
