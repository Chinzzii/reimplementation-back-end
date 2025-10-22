# frozen_string_literal: true

class Team < ApplicationRecord

  # Core associations
  has_many :signed_up_teams, dependent: :destroy
  has_many :teams_users, dependent: :destroy
  has_many :teams_participants, dependent: :destroy
  has_many :users, through: :teams_participants
  has_many :participants, through: :teams_participants

  # The team is either an AssignmentTeam or a CourseTeam
  belongs_to :assignment, class_name: 'Assignment', foreign_key: 'parent_id', optional: true, inverse_of: :teams
  belongs_to :course, class_name: 'Course', foreign_key: 'parent_id', optional: true, inverse_of: :teams
  belongs_to :user, optional: true # Team creator

  attr_accessor :max_participants
  validates :parent_id, presence: true
  validates :type, presence: true, inclusion: { in: %w[AssignmentTeam CourseTeam MentoredTeam],
                                                message: "must be 'AssignmentTeam', 'CourseTeam', or 'MentoredTeam'" }

  def has_member?(user)
    participants.exists?(user_id: user.id)
  end

  def size
    participants.size
  end

  def empty?
    participants.empty?
  end

  def full?
    return false unless is_a?(AssignmentTeam) && assignment&.max_team_size

    participants.count >= assignment.max_team_size
  end

  # Checks if the given participant is already on any team for the associated assignment or course.
  def participant_on_team?(participant)
    ctx = membership_context
    return false unless ctx

    ctx.teams.joins(:teams_participants).where(teams_participants: { participant_id: participant.id }).exists?
  end

  # Adds a participant (or user) to the team if they are eligible.
  def add_member(member)
    participant = normalize_member(member, ensure_context: true)
    return participant if participant.is_a?(Hash)

    # Fail fast if the team is already full.
    return { success: false, error: "Team is at full capacity." } if full?

    eligibility = can_participant_join_team?(participant)
    return eligibility unless eligibility[:success]

    # Use create! to add the participant to the team.
    teams_participants.create!(participant: participant, user: participant.user)
    { success: true }
  rescue ActiveRecord::RecordInvalid => e
    # Catch potential validation errors from TeamsParticipant.
    { success: false, error: e.record.errors.full_messages.join(', ') }
  end

  def remove_member(member)
    participant = normalize_member(member)
    return participant if participant.is_a?(Hash)

    membership = teams_participants.find_by(participant_id: participant.id)
    return { success: false, error: 'Participant is not on this team.' } unless membership

    membership.destroy
    { success: true }
  end

  # Determines whether a given participant or user is eligible to join the team.
  def can_participant_join_team?(member)
    participant = normalize_member(member, ensure_context: true)
    return participant if participant.is_a?(Hash)

    ctx = membership_context
    return { success: false, error: 'Team must belong to an assignment or a course.' } unless ctx

    return { success: false, error: "This user is already assigned to a team for this #{context_label}." } if participant_on_team?(participant)

    # All checks passed; participant is eligible to join the team
    { success: true }
  end

  # Copies the current team into a new team that belongs to the supplied context.
  # The context can be an Assignment or a Course.  You may override the class via `as:`,
  # or the name via `name:`.
  def copy_to(context, as: nil, name: nil)
    target_class = as || self.class.team_class_for(context)
    raise ArgumentError, 'target class must inherit from Team' unless target_class <= Team

    new_team = target_class.new(name: name || self.name)
    apply_context!(new_team, context)
    new_team.save!

    copy_members_to(new_team)
    new_team
  end

  def copy_to_assignment(assignment, as: AssignmentTeam, name: nil)
    copy_to(assignment, as:, name:)
  end

  def copy_to_course(course, as: CourseTeam, name: nil)
    copy_to(course, as:, name:)
  end

  def copy_members_to(target_team)
    errors = []

    participants.includes(:user).each do |participant|
      target_participant = target_team.ensure_participant_enrollment(participant.user)
      result = target_team.add_member(target_participant)
      errors << result[:error] unless result[:success]
    end

    return { success: true, team: target_team } if errors.empty?

    { success: false, error: errors.uniq.join(', ') }
  end

  protected

  def ensure_participant_enrollment(user)
    ctx = membership_context
    raise ArgumentError, 'Team must belong to an assignment or a course.' unless ctx

    self.class.ensure_participant_for_context(user, ctx)
  end

  def membership_context
    assignment || course
  end

  def context_label
    membership_context.is_a?(Assignment) ? 'assignment' : 'course'
  end

  private

  def normalize_member(member, ensure_context: false)
    ctx = membership_context
    return { success: false, error: 'Team must belong to an assignment or a course.' } unless ctx

    participant =
      case member
      when Participant
        member
      when User
        find_participant_for_user(member) ||
          return({ success: false, error: "#{member.name} is not a participant in this #{context_label}." })
      else
        return { success: false, error: 'Member must be a Participant or User.' }
      end

    if ensure_context && !participant_matches_context?(participant)
      return { success: false, error: "#{participant.user.name} is not a participant in this #{context_label}." }
    end

    participant
  end

  def find_participant_for_user(user)
    ctx = membership_context
    return nil unless ctx

    expected_class = self.class.participant_class_for(ctx)
    expected_class.find_by(user_id: user.id, parent_id: ctx.id)
  end

  def participant_matches_context?(participant)
    ctx = membership_context
    return false unless ctx

    participant.is_a?(self.class.participant_class_for(ctx)) && participant.parent_id == ctx.id
  end

  def apply_context!(team, context)
    case context
    when Assignment
      team.assignment = context
      team.parent_id = context.id
    when Course
      team.course = context
      team.parent_id = context.id
    else
      raise ArgumentError, "Unsupported context #{context.class}"
    end
  end

  class << self
    def team_class_for(context)
      case context
      when Assignment
        AssignmentTeam
      when Course
        CourseTeam
      else
        raise ArgumentError, "Unsupported context #{context.class}"
      end
    end

    def participant_class_for(context)
      case context
      when Assignment
        AssignmentParticipant
      when Course
        CourseParticipant
      else
        raise ArgumentError, "Unsupported context #{context.class}"
      end
    end

    def ensure_participant_for_context(user, context)
      participant_class = participant_class_for(context)
      attrs = { user_id: user.id, parent_id: context.id }

      participant_class.find_or_create_by!(attrs) do |participant|
        participant.assignment = context if context.is_a?(Assignment)
        participant.course = context if context.is_a?(Course)
        participant.handle = user.handle.presence || user.name
      end.tap do |participant|
        if participant.handle.blank? && participant.respond_to?(:set_handle)
          participant.assignment = context if context.is_a?(Assignment)
          participant.course = context if context.is_a?(Course)
          participant.set_handle
        end
      end
    end
  end
end
