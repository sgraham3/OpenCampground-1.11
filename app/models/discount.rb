class Discount < ActiveRecord::Base
  has_many :reservations
  acts_as_list
  validate :either_or?
  validates_presence_of :name
  validates_uniqueness_of :name
  validates_numericality_of :amount,
			    :greater_than_or_equal_to => 0.00
  validates_numericality_of :discount_percent,
			    :greater_than_or_equal_to => 0.00,
			    :less_than_or_equal_to => 100.00
  before_destroy :check_use

  ONCE = 1
  PER_DAY = 2
  PER_WEEK = 3
  PER_MONTH = 4

  default_scope :order => :position
  named_scope :active, :conditions => ["active = ?", true]

  def charge(total, units = Charge::DAY, count = 1)
    ActiveRecord::Base.logger.debug "Discount#charge called with total = #{total}, units = #{units}, count = #{count}"
    val = 0.0
    # if this is a percent discount
    if discount_percent > 0.0
      ActiveRecord::Base.logger.debug "Discount#charge percent discount #{discount_percent}"
      case units
      when Charge::DAY
	val =  total * discount_percent / 100.0 if disc_appl_daily
      when Charge::WEEK
	val =  total * discount_percent / 100.0 if disc_appl_week
      when Charge::MONTH
	val =  total * discount_percent / 100.0 if disc_appl_month
      when Charge::SEASON
	val =  total * discount_percent / 100.0 if disc_appl_seasonal
      end
    # if this is an amount discount
    elsif amount > 0.0
      val = amount
      ActiveRecord::Base.logger.debug "Discount#charge amount once #{val}"
    else
      case units
      when Charge::DAY
        val =  amount_daily * count
	ActiveRecord::Base.logger.debug "Discount#charge amount discount daily #{val}"
      when Charge::WEEK
        val =  amount_weekly * count
	ActiveRecord::Base.logger.debug "Discount#charge amount discount weekly #{val}"
      when Charge::MONTH
        val =  amount_monthly * count 
	ActiveRecord::Base.logger.debug "Discount#charge amount discount monthly #{val}"
      when Charge::SEASON
        val =  amount
	ActiveRecord::Base.logger.debug "Discount#charge amount discount season #{val}"
      else
        val =  amount
	ActiveRecord::Base.logger.debug "Discount#charge amount discount other #{val}"
      end
    end
    ActiveRecord::Base.logger.debug "Discount#charge amount is #{val}"
    return val
  end
    
  def self.skip_seasonal?
    # true if no discounts apply to seasonal
    self.all.each {|d| return false if d.disc_appl_seasonal}
    return true
  end

private

  def either_or?
    if (discount_percent != 0.0) && ((amount + amount_daily + amount_weekly + amount_monthly)!= 0.0)
      errors.add(:discount_percent, "specified and amount specified.  Can only have amount or percent not both")
    end
    if (amount != 0.0) && ((amount_daily + amount_weekly + amount_monthly)!= 0.0)
      errors.add(:amount, "Once provided.  Cannot have daily, weekly or monthly if once is selected")
    end
    if (discount_percent != 0.0) && !(disc_appl_daily | disc_appl_week | disc_appl_month | disc_appl_seasonal)
      errors.add(:discount_percent, "specified and no applicability specified.  One of the applies to items must be selected")
    end
  end

  def check_use
    res = Reservation.find_all_by_discount_id id
    if res.size > 0
      lst = ''
      res.each {|r| lst << " #{r.id},"}
      errors.add "discount in use by reservation(s) #{lst}"
      return false
    end
  end

end
