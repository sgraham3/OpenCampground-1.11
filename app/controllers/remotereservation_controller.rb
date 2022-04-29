class RemotereservationController < ApplicationController
  include MyLib
  include CalculationHelper
  include RemotereservationHelper
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

    session[:remotereservation] = true
    session[:controller] = :remotereservation
    session[:action] = :index
    ####################################################
    # new express reservation.  Just make available all of
    # the fields needed for a reservation
    ####################################################

    @spaces  = Space.all()
    @count = @spaces.size
    
    session[:reservation_id] = nil

		if @option.use_closed?
			@closedStart = @option.closed_start.change(:year => currentDate.year)
			@closedEnd = @option.closed_end.change(:year => currentDate.year)
			if @closedEnd > @closedStart
				# start and end are in the same year
				if currentDate > @closedEnd
					@closedStart = @option.closed_start.change(:year => (currentDate.year + 1))
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				end
				debug "Closed summer"
				@closedSummer = true
			else
				# start is in one year and end is in the next year
				@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				if currentDate > @closedEnd
					@closedStart = @option.closed_start.change(:year => (currentDate.year + 1))
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 2))
				else
					@closedEnd = @option.closed_end.change(:year => (currentDate.year + 1))
				end
				debug "Closed winter"
				@closedSummer = false
			end
		end

		@spaces = Space.active
		# getcurrentyear = currentDate.year
		# getcurrentmonth = currentDate.mon
		# getendofcurrentdate = Date.parse("2021-12-31")
		res = Reservation.all( :conditions => [ "(enddate >= ? or checked_in = ?) and confirm = ? and archived = ? or unconfirmed_remote = ? or unconfirmed_remote = ?",currentDate, true, true, false, true, false],
		:include => ['camper'],
				 :order => "space_id,startdate ASC")
		# check for conflicts aka double booking
		res.each do |r|
			sp = Space.confirm_available r.id, r.space_id, r.startdate, r.enddate
			if sp.size > 0
				sp.each do |s|
					if flash[:error]
						flash[:error] +=  " Conflict between #{r.id} and #{s.id}"
					else
						flash[:error] =  "Conflict between #{r.id} and #{s.id}"
					end
				end
			end
		end
		@res = res.group_by{|sp|sp.space_id}
  end

  def check_for_remote
    debug 'check_for remote:'
    unless @option.use_remote_reservations?
      redirect_to '/404.html' and return
    end
  end
end
