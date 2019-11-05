class Map::RegistrationsController < ActionController::Base

  def create
    registration = Registration.new(parameters)
    registration.save!
    render json: {success: true, registration: registration}
  end

  private

  def parameters
    params.permit(:event_id, :name, :email)
  end

end
