module Report::CardTransactionsHelper
  def get_res(id)
    res = Reservation.find id
  rescue
    c = Camper.find_or_create_by_last_name 'unknown'
    res = Reservation.new :camper_id => c
  end
end
