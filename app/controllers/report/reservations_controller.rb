class Report::ReservationsController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login

  # GET /report_reservations/new
  # GET /report_reservations/new.xml
  def new
    @page_title = "Reservations Report Setup"
    @reservation = Reservation.new :startdate => currentDate.beginning_of_year, :enddate => currentDate.beginning_of_month
  end

  # POST /report_reservations
  # POST /report_reservations.xml
  def create
    if params[:csv]
      startdate =  session[:startdate]
      enddate =  session[:enddate]
      # generate the header line
      csv_string = '"Site","startdate","enddate","Name","Address","City","State","ZIP","Net","Taxes","Payments","Disposition"' + "\n"
      # now for the data
      result = get_reservations( startdate, enddate)
      result.each do |r|
        csv_string << "\"#{r.space.name}\",\"#{r.startdate}\",\"#{r.enddate}\",\"#{r.camper.full_name}\",\"#{r.camper.address}\",\"#{r.camper.city}\",\"#{r.camper.state}\",\"#{r.camper.mail_code}\""
        csv_string << ",\"#{r.total}\",\"#{r.tax_amount}\",\"#{Payment.total(r.id)}\",\"#{r.last_log_entry}\"\n"
      end
      send_data(csv_string, 
        :type => 'text/csv;charset=iso-8859-1;header=present',
        :disposition => 'attachment; filename=Occupancy.csv')
    else
      res = Reservation.new(params[:reservation])
      @startdate = res.startdate
      @enddate   = res.enddate
      session[:startdate] = @startdate
      session[:enddate] = @enddate
      @page_title = "Reservations Report #{@startdate} to #{@enddate}"
      @result = get_reservations( @startdate, @enddate)
    end
  end

  def res_date
    @page_title = "Remote Reservations Report"
  end

  def remoteResReport
    @startdate = DateTime.new(params[:reservation]["startdate(1i)"].to_i, params[:reservation]["startdate(2i)"].to_i, params[:reservation]["startdate(3i)"].to_i, 00, 00, 00).strftime('%Y-%-m-%d %H:%M:%S')
    @enddate = DateTime.new(params[:reservation]["enddate(1i)"].to_i, params[:reservation]["enddate(2i)"].to_i, params[:reservation]["enddate(3i)"].to_i, 23, 59, 59).strftime('%Y-%-m-%d %H:%M:%S')

    @result = get_remotereservations("false", @startdate, @enddate)

    render :json => @result
  end

  def allResReport
    @startdate = DateTime.new(params[:reservation]["startdate(1i)"].to_i, params[:reservation]["startdate(2i)"].to_i, params[:reservation]["startdate(3i)"].to_i, 00, 00, 00).strftime('%Y-%-m-%d %H:%M:%S')
    @enddate = DateTime.new(params[:reservation]["enddate(1i)"].to_i, params[:reservation]["enddate(2i)"].to_i, params[:reservation]["enddate(3i)"].to_i, 23, 59, 59).strftime('%Y-%-m-%d %H:%M:%S')

    @result = get_remotereservations(params[:status], @startdate, @enddate)

    render :json => @result
  end

private
  def get_reservations(sd, ed)
    res = Reservation.all(:conditions => ["confirm = ? and startdate <= ? and enddate >= ?", true, ed, sd], 
                          :include => ["camper","space"], :order => :startdate)
  end

  def get_remotereservations(status, sd, ed)
    if status == "true"
      res = Reservation.all(:conditions => ["is_remote = ? and created_at <= ? and created_at >= ?", true, ed, sd],
      :include => ["camper","space"], :order => :startdate)
    else
      res = Reservation.all(:conditions => ["is_remote = ? and unconfirmed_remote = ? and created_at <= ? and created_at >= ?", true, true, ed, sd],
      :include => ["camper","space"], :order => :startdate)
    end
    
    result = Array.new
    for row in res do
      if row.camper
        full_name = row.camper.full_name
        city = row.camper.city
        state = row.camper.state
        mail_code = row.camper.mail_code
      else
        full_name = ''
        city = ''
        state = ''
        mail_code = ''
      end 
      temp = [row.id, row.space.name, row.startdate, row.enddate, full_name, city, state, mail_code, number_2_currency(row.total), number_2_currency(row.tax_amount), number_2_currency(Payment.total(row.id)), row.last_log_entry]
      result << temp
    end
    return result
  end
end
