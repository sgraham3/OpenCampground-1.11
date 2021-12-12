class Admin::UserManualController < ApplicationController

  def index
    if File.exist?  RAILS_ROOT + "/doc/UserManual.pdf"
      send_file RAILS_ROOT + "/doc/UserManual.pdf", :disposition => 'inline'
    elsif File.exist?  RAILS_ROOT + "/doc/User Manual.pdf"
      send_file RAILS_ROOT + "/doc/User Manual.pdf", :disposition => 'inline'
    else
      flash[:error] = "Cannot find User Manual"
      redirect_to :action => :index
    end
  end

end
