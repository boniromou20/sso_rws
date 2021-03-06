require 'net/ldap'
require 'net/ldap/dn'
require 'timeout'
class Openldap < Ldap
  DISABLED_ACCOUNT_KEY = 'disable'
  ADMIN_GROUP = 'PortalAdmins'
  MATCH_PATTERN_REGEXP = /\d+casinoid/

  def retrieve_user_profile(auth_source_detail, username_with_domain, casino_ids)
    ldap = initialize_ldap_con(auth_source_detail, nil, nil)

    search_filter = Net::LDAP::Filter.eq('cn', username_with_domain.split('@')[0])
    ldap_entry = ldap.search(:base => auth_source_detail['data']['base_dn'], :filter => search_filter, :return_result => true, :scope => auth_source_detail['data']['search_scope'] || Net::LDAP::SearchScope_WholeSubtree)
    if ldap_entry.blank?
      Rails.logger.info "[username=#{username_with_domain}] account is not in Open Ldap server "
      return {}
    end
    is_disable_account = ldap_entry.first[:displayname].include?(DISABLED_ACCOUNT_KEY)
    status = is_disable_account ? SystemUser::INACTIVE : SystemUser::ACTIVE

    groups = retrieve_ldap_casino(ldap, auth_source_detail, username_with_domain, casino_ids)

    res = { :status => status, :casino_ids => groups.uniq }
    Rails.logger.info "[username=#{username_with_domain}][filter_groups=#{casino_ids}] account result => #{res.inspect}"
    res
  end

  def retrieve_ldap_casino(ldap, auth_source_detail, username_with_domain, casino_ids)
    user, domain = username_with_domain.split('@')
    username = "cn=#{user},ou=User,#{domain.split('.').map{|d| "dc=#{d}"}.join(',')}"
    search_filter = Net::LDAP::Filter.eq("memberUid", username)
    ldap_entry = ldap.search(:base => auth_source_detail['data']['base_dn'], :filter => search_filter, :return_result => true, :scope => auth_source_detail['data']['search_scope'] || Net::LDAP::SearchScope_WholeSubtree)
    if ldap_entry.blank?
      Rails.logger.info "[username=#{username}][filter_groups=#{casino_ids}] account is not in casino group "
      return []
    end

    memberofs = []
    ldap_entry.each {|entry| memberofs += entry[:cn] }
    Rails.logger.info "Ldap server response: distinguishedName => #{username_with_domain}, memberOf => #{memberofs}"

    groups = filter_memberofs(memberofs, casino_ids)
    if groups.size == 0 && memberofs.join(',').include?(ADMIN_GROUP)
      group_name = "cn=#{ADMIN_GROUP},ou=Group,#{domain.split('.').map{|d| "dc=#{d}"}.join(',')}"
      group_filter = Net::LDAP::Filter.eq("memberUid", group_name)
      group_entry = ldap.search(:base => auth_source_detail['data']['base_dn'], :filter => group_filter, :return_result => true, :scope => auth_source_detail['data']['search_scope'] || Net::LDAP::SearchScope_WholeSubtree)
      group_memberofs = []
      group_entry.each {|entry| group_memberofs += entry[:cn] } if group_entry
      Rails.logger.info "Ldap server response: group => #{group_name}, memberOf => #{group_memberofs}"
      groups = filter_memberofs(group_memberofs, casino_ids)
    end
    groups
  end

  def initialize_ldap_con(auth_source_detail, ldap_user, ldap_password)
    username = ldap_user || auth_source_detail['data']['account']
    user, domain = username.split('@')
    if ldap_user
      username = "uid=#{user},ou=User,#{domain.split('.').map{|d| "dc=#{d}"}.join(',')}"
    else
      username = "cn=#{user},#{domain.split('.').map{|d| "dc=#{d}"}.join(',')}"
    end
    options = { :host => auth_source_detail['data']['host'],
                :port => auth_source_detail['data']['port'] || 3268,
                :encryption => nil,
                :auth => {
                  :method => :simple,
                  :username => username,
                  :password => ldap_password || auth_source_detail['data']['password']
                }
              }
    Net::LDAP.new options
  end

  private

  def filter_memberofs(memberofs, casino_ids)
    groups = []
    memberofs.each do |memberof|
      casino_ids.each do |filter|
        groups << filter.to_i if memberof_has_key?(memberof, MATCH_PATTERN_REGEXP, filter.to_s)
      end
    end
    groups
  end
end
