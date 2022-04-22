class RemotereservationController < ApplicationController
  include MyLib
  include CalculationHelper
  before_filter :check_for_remote
  before_filter :check_dates, :only => [:find_space, :update_dates, :change_space, :express_2]
  # before_filter :set_defaults
  before_filter :cookies_required, :except => [:index]
  before_filter :cleanup_abandoned, :only => [:new, :express, :select_change, :change_space]
  in_place_edit_for :reservation, :adults
  in_place_edit_for :reservation, :pets
  in_place_edit_for :reservation, :kids
  in_place_edit_for :reservation, :length
  in_place_edit_for :reservation, :slides
  in_place_edit_for :reservation, :rig_age
  in_place_edit_for :reservation, :special_request
  in_place_edit_for :reservation, :rigtype_id
  in_place_edit_for :reservation, :vehicle_state
  in_place_edit_for :reservation, :vehicle_license
  in_place_edit_for :reservation, :vehicle_state_2
  in_place_edit_for :reservation, :vehicle_license_2

  def index
    @page_title = I18n.t('titles.express')
    debug 'In remote index'
    session[:remotereservation] = true
    session[:controller] = :remotereservation
    session[:action] = :index
    ####################################################
    # new express reservation.  Just make available all of
    # the fields needed for a reservation
    ####################################################

    session[:payment_id] = nil
    session[:reservation_id] = nil
    @reservation = Reservation.new
    @reservation.startdate = currentDate
    @reservation.enddate = @reservation.startdate + 1
    unless Campground.open?(@reservation.startdate, @reservation.enddate)
      flash.now[:warning] = I18n.t('reservation.Flash.ClosedDates', :closed => DateFmt.format_date(@option.closed_start), :open => DateFmt.format_date(@option.closed_end))
      @reservation.startdate = Campground.next_open
      @reservation.enddate = @reservation.startdate + 1
    end
    if @option.use_reserve_by_wk
      y,w,d = Date::jd_to_commercial(Date::civil_to_jd(@reservation.startdate.year,
                                                       @reservation.startdate.month,
                                                       @reservation.startdate.day))
      session[:count] = 0
      session[:number] = w
      session[:year] = y
    end
    session[:startdate] = @reservation.startdate  
    session[:enddate] = @reservation.enddate
    @seasonal_ok = false
    @storage_ok = false
    # we will not save the res because if we will 
    # need it later it is already saved
    @spaces  = Space.all()
    @count = @spaces.size
    @extras = Extra.active
    session[:canx_action] = 'abandon'
    session[:change] = 'false'
  end

  def check_for_remote
    debug 'check_for remote:'
    unless @option.use_remote_reservations?
      redirect_to '/404.html' and return
    end
  end
end
