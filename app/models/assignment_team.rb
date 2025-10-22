# frozen_string_literal: true

class AssignmentTeam < Team
  # Each AssignmentTeam must belong to a specific assignment
  belongs_to :assignment, class_name: 'Assignment', foreign_key: 'parent_id', inverse_of: :teams

  def copy_to_course(course, name: "#{self.name} (Course)")
    copy_to(course, as: CourseTeam, name:)
  end

  def copy_to_assignment(assignment, as: AssignmentTeam, name: self.name)
    copy_to(assignment, as:, name:)
  end
end 
