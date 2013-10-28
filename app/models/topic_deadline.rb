class TopicDeadline < ActiveRecord::Base
  belongs_to :topic, :class_name => 'SignUpTopic'

  validate :due_at_is_valid_datetime

  def due_at_is_valid_datetime
    errors.add(:due_at, 'must be a valid datetime') if ((DateTime.strptime(due_at.to_s, '%Y-%m-%d %H:%M:%S') rescue ArgumentError) == ArgumentError)
  end

  def topic_due_date(drop_topic_deadline_id,topic_id)
    if topic_id
      # next for topic
      next_due_date = self.find(:first, :conditions => ['topic_id = ? and due_at >= ? and deadline_type_id <> ?', topic_id, Time.now, drop_topic_deadline_id], :order => 'due_at')
    else
      # next for assignment
      next_due_date = self.find(:first, :conditions => ['assignment_id = ? and due_at >= ? and deadline_type_id <> ?', self.id, Time.now, drop_topic_deadline_id], :joins => {:topic => :assignment}, :order => 'due_at')
    end
    return next_due_date
  end

  def find_next_due_date(topic_id,assignment_id)
    drop_topic_deadline_id = DeadlineType.find_drop_topic_deadline_id()
    if topic_id
      TopicDeadline.find(:first, :conditions => ['topic_id = ? and due_at >= ? and deadline_type_id <> ?', topic_id, Time.now, drop_topic_deadline_id], :order => 'due_at')
    else
      TopicDeadline.find(:first, :conditions => ['assignment_id = ? and due_at >= ? and deadline_type_id <> ?', assignment_id, Time.now, drop_topic_deadline_id], :joins => {:topic => :assignment}, :order => 'due_at')
    end
  end
end
