class ReportController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login

  def index
    @page_title = "Reports"
    @integration = Integration.first
  end
end
