# frozen_string_literal: true

class CourseTeam < Team
  #Each course team must belong to a course
  belongs_to :course, class_name: 'Course', foreign_key: 'parent_id', inverse_of: :teams

  def copy_to_assignment(assignment, as: AssignmentTeam, name: "#{self.name} (Assignment)")
    copy_to(assignment, as:, name:)
  end

  def copy_to_course(course, name: self.name)
    copy_to(course, as: CourseTeam, name:)
  end
end 
