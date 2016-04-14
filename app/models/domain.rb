class Domain < ActiveRecord::Base
  attr_accessible :id, :name

  has_many :system_users
  has_many :domains_casinos
  has_many :casinos, :through => :domains_casinos

  validates_presence_of :name, :message => 'domain name can not be empty'
  validates_uniqueness_of :name

  validates_format_of :name, :with => /^[a-zA-Z0-9][-a-zA-Z0-9]{0,62}(\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})+$/, :on => :create

  def get_casino_ids
    domains_casinos.pluck(:casino_id)
  end

  def self.validate_domain!(domain)
    raise Rigi::InvalidDomain.new(I18n.t("alert.invalid_domain")) if domain.blank? || !Domain.where(:name => domain).first
  end

  def self.insert(params)
    name = params[:name].downcase
    create!(name: name)
  end
end
