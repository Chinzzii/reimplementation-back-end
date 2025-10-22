class TeamsController < ApplicationController
  # Set the @team instance variable before executing actions except index and create
  before_action :set_team, except: [:index, :create]

  # Validate team type only during team creation
  before_action :validate_team_type, only: [:create]

  # GET /teams
  # Fetches all teams and renders them using TeamSerializer
  def index
    @teams = Team.all
    render json: @teams, each_serializer: TeamSerializer
  end

  # GET /teams/:id
  # Shows a specific team based on ID
  def show
    render json: @team, serializer: TeamSerializer
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Team not found' }, status: :not_found
  end

  # POST /teams
  # Creates a new team associated with the current user
  def create
    @team = Team.new(team_params)
    @team.user = current_user
    if @team.save
      render json: @team, serializer: TeamSerializer, status: :created
    else
      render json: { errors: @team.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /teams/:id/members
  # Lists all members of a specific team
  def members
    participants = @team.participants.includes(:user)
    render json: participants.map(&:user), each_serializer: UserSerializer
  end

  # POST /teams/:id/members
  # Adds a new member to the team.
  def add_member
    user = User.find(team_participant_params[:user_id])
    result = @team.add_member(user)

    if result[:success]
      render json: user, serializer: UserSerializer, status: :created
    else
      render json: { errors: [result[:error]] }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { errors: ['User not found'] }, status: :not_found
  end

  # DELETE /teams/:id/members/:user_id
  # Removes a member from the team based on user ID
  def remove_member
    user = User.find(params[:user_id])
    result = @team.remove_member(user)

    if result[:success]
      head :no_content
    else
      render json: { errors: [result[:error]] }, status: :not_found
    end
  rescue ActiveRecord::RecordNotFound
    render json: { errors: ['User not found'] }, status: :not_found
  end

  # Placeholder method to get current user (can be replaced by actual auth logic)
  def current_user
    @current_user
  end

  private

  # Finds the team by ID and assigns to @team, else renders not found
  def set_team
    @team = Team.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Team not found' }, status: :not_found
  end

  # Whitelists the parameters allowed for team creation/updation
  def team_params
    params.require(:team).permit(:name, :max_team_size, :type, :assignment_id, :course_id, :parent_id)
  end

  # Whitelists parameters required to add a team member
  def team_participant_params
    params.require(:team_participant).permit(:user_id)
  end

  # Validates the team type before team creation to ensure it's among allowed types
  def validate_team_type
    # Use .dig to safely access nested params.
    # Check that the type is present AND included in the list.
    team_type = params.dig(:team, :type)

    unless team_type.in?(['CourseTeam', 'AssignmentTeam', 'MentoredTeam'])
      # If type is nil or not in the list, render an error and stop execution.
      render json: { errors: ["Invalid or missing team type. Must be one of: CourseTeam, AssignmentTeam, MentoredTeam."] },
             status: :unprocessable_entity
    end
  end
end 
