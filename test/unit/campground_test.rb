require 'test_helper'

class CampgroundTest < ActiveSupport::TestCase
  fixtures :options

  # Replace this with your real tests.
  def setup
  end

  def test_opened
    opt = Option.first

    # closed for summer
    # the campground is closed from may 1 to sept 30
    opt.update_attributes :closed_start => Date.new(2013,5,1), :closed_end => Date.new(2013,10,1), :use_closed => false
    start_date = Date.new(2013,5,1) ; end_date = Date.new(2013,5,10)
    assert Campground.open?(start_date, end_date) # 0 true use_closed is false
    opt.update_attributes :use_closed => true # use_closed is true
    start_date = Date.new(2013,3,1) ; end_date = Date.new(2013,3,10)
    assert Campground.open?(start_date, end_date) # 1 true - start and end before closed period
    start_date = Date.new(2013,3,31) ; end_date = Date.new(2013,6,1)
    assert !Campground.open?(start_date, end_date) # 2 false - end date in closed period
    start_date = Date.new(2013,6,1) ; end_date = Date.new(2013,10,10)
    assert !Campground.open?(start_date, end_date) # 3 false - start date in closed period
    start_date = Date.new(2013,10,2) ; end_date = Date.new(2013,11,1)
    assert Campground.open?(start_date, end_date) # 4 true - start and end after closed period
    start_date = Date.new(2013,4,11) ; end_date = Date.new(2013,10,11)
    assert !Campground.open?(start_date, end_date) # 5 false - start date before end date after closed period 
    start_date = Date.new(2013,10,1) ; end_date = Date.new(2013,11,1)
    assert !Campground.open?(start_date, end_date) # 6 false - start date on closed end
    start_date = Date.new(2013,3,1) ; end_date = Date.new(2013,5,1)
    assert  Campground.open?(start_date, end_date) # 7 true - end date on closed start
    start_date = Date.new(2013,6,1) ; end_date = Date.new(2013,6,1)
    assert !Campground.open?(start_date, end_date) # 8 false - end date == start date in closed period
    start_date = Date.new(2013,10,5) ; end_date = Date.new(2013,10,5)
    assert Campground.open?(start_date, end_date) # 9 true - end date == start date not in closed period
    # closed for winter
    # the campground is closed from nov 1 to march 31 of the next year
    opt.update_attributes :closed_start => Date.new(2014,11,1), :closed_end => Date.new(2014,3,31)
    start_date = Date.new(2013,10,1) ; end_date = Date.new(2013,10,10)
    assert Campground.open?(start_date, end_date) # 1 true - start and end before closed period
    start_date = Date.new(2013,10,1) ; end_date = Date.new(2013,12,10)
    assert !Campground.open?(start_date, end_date) # 2 false - end date in closed period
    start_date = Date.new(2014,3,1) ; end_date = Date.new(2014,4,10)
    assert !Campground.open?(start_date, end_date) # 3 false - start date in closed period     
    start_date = Date.new(2014,4,1) ; end_date = Date.new(2014,4,10)
    assert Campground.open?(start_date, end_date) # 4 true - start and end after closed period
    start_date = Date.new(2013,10,1) ; end_date = Date.new(2014,4,10)
    assert !Campground.open?(start_date, end_date) # 5 false - start date before end date after closed period
    start_date = Date.new(2014,3,31) ; end_date = Date.new(2014,4,10)
    assert !Campground.open?(start_date, end_date) # 6 false - start date on closed end
    start_date = Date.new(2013,9,1) ; end_date = Date.new(2013,10,1)
    assert Campground.open?(start_date, end_date) # 7 true - end date on closed start
    start_date = Date.new(2014,2,1) ; end_date = Date.new(2014,2,1)
    assert !Campground.open?(start_date, end_date) # 8 false - end date == start date in closed period
    start_date = Date.new(2014,4,5) ; end_date = Date.new(2014,4,5)
    assert Campground.open?(start_date, end_date) # 9 true - end date == start date not in closed period
  end

end
