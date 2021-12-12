class Camper < ActiveRecord::Base
  include MyLib

  attr_accessor_with_default :remote, false
  has_many :reservations
  has_many :groups
  belongs_to :country
  validates_presence_of :last_name, :message => I18n.t('warning.LastName')
  validate :required_fields?
  before_destroy :check_use
  
  default_scope :order => "last_name, first_name asc"

  def before_save
    # check that names do not start with blank..
    # take the blanks off
    if self.last_name_changed?
      self.last_name = self.last_name.strip
    end
  rescue => err
    ActiveRecord::Base.logger.debug 'Camper#before_save ' + err.to_s
  end

  def full_name
    # concatinate first and last name for output
    [first_name, last_name].join(' ')
  end

  def active
    self.update_attribute(:activity, currentDate )
  end

  private

  def check_use
    res = Reservation.find_all_by_camper_id id
    grp = Group.find_all_by_camper_id id
    if res.size + grp.size > 0
      r_lst = ''
      g_lst = ''
      if res.size > 0
	res.each {|r| r_lst << " #{r.id},"}
	errors.add "camper in use by reservation(s) #{r_lst}"
      end
      if grp.size > 0
	grp.each {|g| g_lst << " #{g.id},"}
	errors.add "camper in use by group(s) #{g_lst}"
      end
      return false
    end
  end

  def required_fields?
    option = Option.first
    if remote
      errors.add :first_name, I18n.t('warning.FirstName') if option.require_first? && first_name.empty?
      errors.add :address,    I18n.t('warning.Addr')      if option.require_addr? && address.empty? 
      errors.add :city,       I18n.t('warning.City')      if option.require_city? && city.empty?
      errors.add :state,      I18n.t('warning.State')     if option.require_state? && state.empty?
      errors.add :mail_code,  I18n.t('warning.Zip')       if option.require_mailcode? && mail_code.empty?
      errors.add :phone,      I18n.t('warning.Phone')     if option.require_phone? && phone.empty?
      if email.empty? 
	errors.add :email,      I18n.t('warning.Email')     if option.require_email?
      else
	errors.add :email,      I18n.t('warning.Email')     unless email.include?("@")
      end
      errors.add :country,    I18n.t('warning.Country')   if option.require_country? && option.use_country && !Country.find(country_id).name
      errors.add :idnumber,   I18n.t('warning.IdNumber')  if option.require_id? && option.use_id? && idnumber.empty?
    else
      errors.add :first_name, I18n.t('warning.FirstName') if option.l_require_first? && first_name.empty?
      errors.add :address,    I18n.t('warning.Addr')      if option.l_require_addr? && address.empty? 
      errors.add :city,       I18n.t('warning.City')      if option.l_require_city? && city.empty?
      errors.add :state,      I18n.t('warning.State')     if option.l_require_state? && state.empty?
      errors.add :mail_code,  I18n.t('warning.Zip')       if option.l_require_mailcode? && mail_code.empty?
      errors.add :phone,      I18n.t('warning.Phone')     if option.l_require_phone? && phone.empty?
      errors.add :email,      I18n.t('warning.Email')     if option.l_require_email? && email.empty?
      errors.add :email,      I18n.t('warning.Email')     if option.l_require_email? && !email.include?("@")
      errors.add :country,    I18n.t('warning.Country')   if option.l_require_country? && !Country.find(country_id).name
      errors.add :idnumber,   I18n.t('warning.IdNumber')  if option.l_require_id? && option.use_id? && idnumber.empty?
    end
  end

end
