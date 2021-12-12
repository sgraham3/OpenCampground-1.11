require 'test_helper'

class DiscountTest < ActiveSupport::TestCase
  fixtures :discounts

  def test_uniqueness_of_name
    disc0 = Discount.create :name => 'validname', :amount => 1.0
    # create with reused name
    disc = Discount.new :name => 'validname', :amount => 1.0
    assert !disc.valid?
    assert disc.errors.invalid?(:name)
    # change the name
    disc.name = 'anothername'
    assert disc.valid?
  end

  def test_presense_of_name
    # create without name
    disc = Discount.new :amount => 1.0
    assert !disc.valid?
    assert disc.errors.invalid?(:name)
    # put on name
    disc.name = "anything"
    # validate with name
    assert disc.valid?
  end

  def test_range
    disc = Discount.new :name => 'test', :discount_percent => 8.00
    assert disc.valid?
    disc.discount_percent = -0.01
    assert !disc.valid? # no negative discount
    disc.discount_percent = 100.01
    assert !disc.valid? # no more than 100% discount
    disc.discount_percent = 100.00
    assert disc.valid?
    disc.amount = 100.00
    assert !disc.valid? # cannot have both percent and amount
    disc.discount_percent = 0.00
    assert disc.valid?
    disc.amount = -100.00
    assert !disc.valid? # no negative discount
  end

  def test_charges
    disc = Discount.new :name => 'test', :discount_percent => 8.00 
    assert_equal disc.charge(100.0), 8.00 # 8% discount
    disc.update_attribute :disc_appl_daily, false
    assert_equal disc.charge(100.0), 0.00 # disc does not apply to any so 0.0
    disc.update_attribute :disc_appl_week, true
    assert_equal disc.charge(100.0, Charge::WEEK), 8.00 
    assert_equal disc.charge(100.0, Charge::WEEK,2), 8.00 # same results no matter how many weeks
    disc.update_attributes :discount_percent => 0.00,
			   :amount => 1.23
    assert_equal  disc.charge(100.0, Charge::DAY, 2), 1.23 # default ONCE 
    assert_equal disc.charge(100.0, Charge::WEEK, 2), 1.23 # default ONCE
    assert_equal disc.charge(100.0, Charge::MONTH, 2), 1.23 # default ONCE
    disc.update_attributes :amount => 0.0, :amount_daily => 1.23
    assert_equal disc.charge(100.0, Charge::DAY, 2), 2.46 # per day * 2 days
    assert_equal disc.charge(100.0, Charge::WEEK, 2), 0.00 # per day * 2 weeks == 0
    assert_equal disc.charge(100.0, Charge::MONTH, 2), 0.00 # per day * 2 months == 0
    disc.update_attributes :amount_weekly => 2.34
    assert_equal disc.charge(100.0, Charge::DAY, 2), 2.46 # per week * 2 days == 0
    assert_equal disc.charge(100.0, Charge::WEEK, 2), 4.68 # per week * 2 weeks == 2.46
    assert_equal disc.charge(100.0, Charge::MONTH, 2), 0.00 # per week * 2 months == 0
    disc.update_attributes :amount_monthly => 3.45
    assert_equal disc.charge(100.0, Charge::DAY, 2), 2.46 # per month * 2 days == 0
    assert_equal disc.charge(100.0, Charge::WEEK, 2), 4.68 # per month * 2 weeks == 0
    assert_equal disc.charge(100.0, Charge::MONTH, 2), 6.90 # per month * 2 months == 0
  end

end
